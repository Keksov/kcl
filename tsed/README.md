# tsed — `TSed`, the GNU `sed` wrapper

> **Status: COMPLETE (P0 + P1).** `TSed : TUtil` is the whole unit — the class,
> the pinned argv, the rc 2 list with the owner's deny-list, the `mapRc`
> override, the five overridden sinks, `paths` / `addExpr` / `clearExprs`, the
> destructor, the static `TSed.edit`, the bench and the docs — plus the
> `TUTIL_OUT_SUFFIXES` registry this unit introduced in
> [`../tutil`](../tutil/README.md). Suite: `tests/004_Argv.sh` (146),
> `tests/005_Run.sh` (70), `tests/006_Contract.sh` (66), `tests/007_Bench.sh`
> (11) — **293 checks green on bash 5.2.37 and 293 on bash 5.3.9**, threaded and
> (5.2.37) under `--mode single`, against **GNU sed 4.9** (5.2.37 resolves Git
> for Windows' `sed.exe`, 5.3.9 msys64's; both 4.9, byte-identical in every
> probe). What the tests pin, case by case:
> **[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md)**. Design record:
> [PLAN.md](PLAN.md) (§2.0 holds the six owner decisions Q1–Q6, §8 the critic
> pass) and [tsed_ledger.json](tsed_ledger.json). The base:
> [`../tutil/README.md`](../tutil/README.md); the siblings:
> [`../tgrep`](../tgrep/README.md), [`../thead`](../thead/README.md),
> [`../ttail`](../ttail/README.md), [`../tfind`](../tfind/README.md).
>
> **Three things were tightened against the real tool at P0 and its review**,
> and they are what the tests pin: the **`sandbox` property fails closed**
> (`--sandbox` is dropped only for the exact string `0`); **`--` among the
> extras is rc 2** (it turned the expressions into operands); and the
> **deny-list follows sed's own getopt** — unambiguous long-option abbreviations
> (`--in=.bak`, `--expr=p`, `--null`, `--sand`) and attached short arguments
> (`-i.bak`, `-es/a/b/`) are the same options and are refused too. One plan fact
> was corrected: **`*` in the in-place suffix is the operand AS GIVEN**, directory
> part included, not its base name (§6).

`TSed` is a [`TUtil`](../tutil/README.md) descendant: typed properties instead
of a hand-built command string, one rc convention, and the five `TPipe` sinks.

```bash
source kcl/tsed/tsed.sh

TSed.edit 's/foo/bar/' notes.txt       # the one-liner: `sed --sandbox -e EXPR -- notes.txt`

TSed.new s 's/a/A/' in.txt             # or an instance, for options
s.addExpr '/^#/d'                      # more expressions, emitted in call order
s.extended = 1                         # -E — always emitted BEFORE the first -e
s.toArray lines                        # RESULT = ${#lines[@]}
s.each r.onLine                        # one call per record, THIS shell
s.count                                # RESULT = how many
s.lastRc                               # RESULT = sed's RAW exit status

s.inPlace = 1                          # in-place: `run` only, the sinks refuse
s.backupSuffix = .bak
s.run
s.delete
```

What it buys over spelling the command out: every option is emitted **before**
the first `-e` whatever order the caller assigned in (sed compiles each `-e` as
it reads it), the sandbox is on unless the caller says `0`, an option that would
duplicate a typed property is refused **before** anything runs, sed's
`0`/`1`/`2`/`4`/`q N` statuses collapse onto the kcl rc convention while the raw
status stays readable, a CRLF file edited in place keeps its CRs, and the
platform notes (text mode, `-z`, the in-place suffix, `--debug` on stdout) live
here instead of in every script.

---

## 0. The six owner decisions (PLAN §2.0)

| Q | decision | where |
|---|---|---|
| **Q1** sandbox | `sandbox = 1` by default and **fail-closed**: `--sandbox` is omitted only when `sandbox` is exactly `0`. `e`, `s///e`, `r`, `R`, `w`, `W`, `s///w` are refused by sed itself. A named deviation from tool parity | §4 |
| **Q2** expressions | both `var expr` (the common case, the constructor's first argument) and `addExpr` / `clearExprs` over `${inst}_exprs`; `expr` first, then the list in order; plus `scriptFile` for `-f` | §3 |
| **Q3** rc | `0 → 0`; `1`, `2`, `4` → rc 1 + one `kk.debug` line worded "sed exited N (a sed error, or the script's q/Q N)"; `127` the base wording; any other status (a script's `q N` / `Q N`) → rc 1 **silent**, the raw value in `lastRc` | §2 |
| **Q4** in-place | `inPlace` + `backupSuffix`; `run` works; the five sinks answer rc 2 when `inPlace = 1` | §6 |
| **Q5** CRLF | `inPlace = 1` and `nullData = 1` **derive `-b`** in `buildArgv`; the `binary` property is never written | §5 |
| **Q6** extras | a **deny-list** in `buildArgv`: an extra that sed's getopt reads as a modelled option is rc 2 with a line naming the property to use; `--` among the extras is rc 2 too | §2 |

---

## 1. Surface

```bash
TSed.new INST [EXPR [PATH...]]         # EXPR -> expr, the rest are paths
```

| Member | Kind | Flag | Notes |
|---|---|---|---|
| `expr` | var | `-e EXPR` | the **first** expression; `''` = none (the identity is `addExpr ''`) |
| `addExpr EXPR...` | proc | `-e X` each | appended after `expr`, in call order; an **empty** argument is a real element (`-e ''`) |
| `clearExprs` | proc | — | empties the list; `expr` is left alone |
| `scriptFile` | var | `-f FILE` | `''` = off; emitted **after** the expressions |
| `extended` | var | `-E` | |
| `quiet` | var | `-n` | |
| `separate` | var | `-s` | implied by `-i` anyway |
| `nullData` | var | `-z` | NUL records; **derives** the sinks' `-0` and the `-b` (§5) |
| `binary` | var | `-b` | keep the CR (§5); also derived, never written by the wrapper |
| `sandbox` | var | `--sandbox` | **default 1** (owner Q1, §4); **fails closed** — off only for the exact string `0` |
| `inPlace` | var | `-i` | derives `-b`; the five sinks refuse it (§6) |
| `backupSuffix` | var | `-iSUFFIX` | attached to `-i`; only with `inPlace = 1` |
| `paths PATH...` | proc | `-- PATH...` | **replaces** the operand list; no argument = stdin |
| `buildArgv` | func | — | override; fills `${inst}_argv`, RESULT = word count |
| `mapRc RAW` | func | — | override; §2 |
| `each` `toArray` `toList` `first` `count` | overrides | — | refuse `inPlace` / `--debug` (rc 2), else the base sink |
| `TSed.edit EXPR PATH...` | static proc | — | §7 |

Inherited from TUtil unchanged: `cmd` (`sed`), `crlf`, `nul`, `_lastRc`,
**`subshellOk`**, `addArg`, `clearArgs`, `argv NAME`, `run`, `lastRc`.

**`subshellOk` (D6 final)** is inherited, not redeclared, default `0`:
`s.subshellOk = 1` makes every sink pass `-s` to `TPipe`, which silences the
warning `$(s.toArray a)` otherwise prints (*Warning: TPipe.toArray: the array a
is filled inside a subshell …*) — the array is filled in the subshell and lost
with it either way; the switch only says the caller knows.

A `var` is read as `$(s.expr)` and written as `s.expr = value`. A boolean is on
for the exact string **`1`** and off for anything else (`2`, `yes`, `true`,
`01`, `' 1'` are all off) — **except `sandbox`, which fails closed**: it is off
only for the exact string **`0`**, and every other value (`''`, `yes`, `2`,
`' 0'`, `'0 '`, `00`, `-0`, `false`, `off`) keeps `--sandbox`. That is **the one
deliberate exception** to the family rule, because the sandbox is a security
default (owner Q1, §4): a typo must not open it.

### The argv, pinned

```
sed [--sandbox] [-E] [-n] [-s] [-z] [-b] [-i[SUFFIX]] [EXTRA OPTIONS from addArg]
    [-e EXPR] [-e X ...] [-f FILE] [-- PATH...]
```

* **Every option precedes the first `-e`.** sed compiles each `-e` *when it
  reads it*, with the flags known so far: `sed -e 's/(a)1/[\1]/' -E` is rc 1
  (*invalid reference \1*), and `sed -e 's/(/X/' -E` silently runs the
  expression as BRE. The order is this builder's, not the order the caller
  assigned in — `extended = 1` set after `addExpr` still lands first.
* Extras from `addArg` land after the typed options and before the first `-e`.
* `-b` appears **once**, when `binary = 1` **or** `inPlace = 1` **or**
  `nullData = 1` (§5).
* `--` appears only with at least one path; with none sed reads stdin, and the
  path `-` is stdin explicitly. A path beginning with `-` is safe behind it.
* Several `-e` are joined with newlines into ONE script, so a block may span
  chunks (`-e '1{' -e 's/a/J/' -e '}'`). Two sed rules follow from the join:
  `#n` as the first line of the first chunk forces `-n`, and an expression that
  ends in `a\` swallows the next chunk (even a `-f` script) as text.

`s.argv NAME` builds the array and **runs nothing** — that is how
`tests/004_Argv.sh` pins every option without executing sed.

---

## 2. Return contract

`rc 0` = sed did everything asked. `rc 1` = it did not (or the script chose a
non-zero exit). `rc 2` = the **call** was malformed and nothing ran. The raw
status stays readable through `lastRc`.

### The rc 2 list — a malformed call, and nothing runs

`buildArgv` answers **rc 2** with `RESULT=''`, one `kk.debug` line naming the
reason, and `${inst}_argv` left empty; every runner passes the 2 straight back
and `lastRc` stays `-1` on a fresh instance.

| refusal | why |
|---|---|
| `cmd` is empty | the instance was disarmed by hand |
| **no script at all** — `expr` `''`, the list empty, `scriptFile` `''` | sed would take the first path **as the script** (`unknown command`) |
| `inPlace = 1` with no path, or with the path `-` anywhere | sed cannot edit stdin in place |
| `backupSuffix` set with `inPlace = 0` | the suffix only means something to `-i` |
| `backupSuffix = '*'` | the backup name would equal the file's: **no backup, silently** |
| an extra on the **deny-list** (owner Q6, below) | it would duplicate a typed property or break the record stream |
| **`--` among the extras** | it ends sed's options before the first `-e`, so every expression would become an operand (measured: `sed --sandbox -- -e s/a/A/ -- f`); the wrapper emits its own `--` before the paths |

No expression text is validated by the wrapper — sed compiles it (a bad
script is sed's rc 1). The five sinks add two refusals of their own (§6):
`inPlace = 1` and `--debug` among the extras.

### The deny-list (owner Q6)

An `addArg` word that sed's getopt reads as one of the modelled options is rc 2,
and the line names the property to use instead:

| sed option | property |
|---|---|
| `-i`, `--in-place[=…]` | `inPlace` / `backupSuffix` |
| `-z`, `--null-data`, `--zero-terminated` | `nullData` |
| `-e`, `--expression[=…]` | `expr` / `addExpr` |
| `-f`, `--file[=…]` | `scriptFile` |
| `-n`, `--quiet`, `--silent` | `quiet` |
| `-s`, `--separate` | `separate` |
| `-E`, `-r`, `--regexp-extended` | `extended` |
| `-b`, `--binary` | `binary` |
| `--sandbox` | `sandbox` |

The scan follows getopt, because getopt is what decides what sed does — it is
**abbreviation-aware**:

* a **bundle** is split: `-ni` is `-n -i`, `-us` contains `-s`, `-ui` contains
  `-i`; an argument attached to a short option is part of it — `-i.bak` is
  `-i`, `-ni.bak` is `-n -i.bak`, `-es/a/b/` is `-e`, `-fscript` is `-f`;
* a long option is matched by **unambiguous prefix**, as getopt does — measured
  on sed 4.9, `--in=.bak` edits the file in place with rc 0, and `--in`,
  `--expr=p`, `--fi=s.sed`, `--null`, `--zero`, `--qui`, `--sil`, `--sep`,
  `--reg`, `--bin` and `--sand` all work — and `--zero-terminated` is an
  undocumented alias of `-z`; a long form with `=VALUE` sed would itself reject
  (`--sandbox=1`, `--quiet=1`) is refused too;
* `-l` is the one allowed option that takes an argument, so the scan stops
  there: `-l 40`, `-l40`, `-ul40` pass;
* the whole list is scanned: a denied word that is not the first extra is
  refused as well.

Everything else passes: `--posix`, `-u`/`--unbuffered`, `-l N`/`--line-length=N`,
`--follow-symlinks`, `--debug` (but see §6: the sinks refuse `--debug`).

### mapRc (owner Q3)

| raw | member | line of ours |
|---|---|---|
| `0` | 0 | — |
| `1` bad script, `2` a missing input file, `4` an I/O error | 1 | one: `sed exited N (a sed error, or the script's q/Q N)` |
| `127` | 1 | the base wording |
| anything else — a script's `q N` / `Q N` (N mod 256) | 1 | **none** — the raw value is in `lastRc` |

A script's `q1`, `q2` and `q4` cannot be told apart from sed's own codes; the
line is worded to say so. `q256` wraps to 0 and is rc 0.

### The five named deviations

**(a) Partial output is kept, and rc 2 and rc 4 differ.** A missing input file
among good ones (raw 2): sed still processes the **other** files; the sinks keep
every record, `RESULT` is the real count, the member answers rc 1. An I/O error
(raw 4 — a directory operand, a missing `-f` script, a failed backup rename)
**stops** at that operand: earlier records are kept, later files are never read
(never edited). The family contract per sink, pinned in 005 §C:

| sink | a missing file among good ones |
|---|---|
| `count` / `toArray` / `toList` | rc 1, RESULT = the real count |
| `each` | rc 1, every record delivered, RESULT untouched (a proc) |
| `first` | rc 0, the first record, `lastRc` 2, **no** line of ours (TUtil's consumer-stop rule) |

**(b) sed's own stderr passes through unconditionally** (`sed: can't read …`,
`sed: -e expression #1, char 3: …`) — the tool's stream, not gated by
`VERBOSE_KKLASS`, locale-quoted, matched by prefix in the tests. Exactly one
line of ours accompanies it under the switch.

**(c) `sandbox = 1` by default, and it fails closed** (owner Q1) — §4.

**(d) A script's `q N` / `Q N` status is not an error** — rc 1, silent, raw in
`lastRc` (above).

**(e) `inPlace` and `nullData` derive `-b`** (owner Q5) — §5.

Two more are the family's, inherited from [tutil](../tutil/README.md): `run`
**streams** to stdout by definition, and for the counting sinks rc 1 means the
tool exited non-zero while `RESULT` still carries the count.

### `$( )` loses the instance's state, and `set -e`

Under `$( )` every mutation is lost with the subshell: `$(s.run)` captures the
bytes but `_lastRc` is not updated. rc 1 is a normal answer here, so a `set -e`
script writes `s.count || rc=$?` — an unguarded sink call with rc 1 aborts the
caller (pinned in `tests/006_Contract.sh`).

---

## 3. Expressions

* `expr` is the constructor's first argument and the **first** `-e`; `''` means
  *none*.
* `addExpr EXPR...` appends; an empty argument keeps its slot (`-e ''`);
  `clearExprs` empties the list (not `expr`); `addExpr` with no argument is a
  no-op.
* `scriptFile` adds `-f FILE` after all the expressions; a missing FILE is sed's
  **rc 4** (`couldn't open file`), no record at all.
* The identity is `addExpr ''` (`-e ''`), never `expr = ''`.
* An expression holding a newline is ONE argv word.

```bash
TSed.new s '2{' data.txt
s.addExpr 's/b/J/' '}'                 # sed --sandbox -e '2{' -e 's/b/J/' -e '}' -- data.txt
```

`${inst}_exprs` is the unit's own storage: it is on the out-name registry (§8),
so `s.toArray s_exprs` cannot turn the records into the next run's script.

---

## 4. The sandbox (owner Q1)

`sandbox = 1` is the default: `--sandbox` makes sed refuse, **at compile time**,
every command that runs a program or touches a file other than stdout:

| refused | what it would do |
|---|---|
| `e COMMAND`, `s///e` | run a shell command |
| `r FILE`, `R FILE` | read an arbitrary file into the stream |
| `w FILE`, `W FILE`, `s///w FILE` | write an arbitrary file — **including `s/a/A/w /dev/stdout`** |

It is total: a refused command in a later `-e` or inside a `-f` script refuses
the whole run (rc 1, sed's *e/r/w commands disabled in sandbox mode*, no record,
nothing executed or written — the tests prove it with marker files). Two
consequences:

* the common idiom **`s/a/A/w /dev/stdout` is refused too — use `p`**;
* `--sandbox` limits the **script**, not in-place editing: `inPlace` still
  writes the file. `F`, `=` and `l` are allowed and print to stdout (they
  arrive as records).

A caller who needs those commands says so: `s.sandbox = 0` — the exact string
`0` and nothing else. The property **fails closed**: `''`, `yes`, `2`, `' 0'`,
`'0 '`, `00`, `-0`, `false`, `off` all keep `--sandbox` (the one exception to
the family's "on only for `1`" boolean rule, §1). `TSed.edit` forces the sandbox
and has no way to turn it off.

**Trap — callbacks declare `local`.** A callback that assigns a bare
`expr=`, `quiet=`, `inPlace=` or `sandbox=0` writes the **instance's** property
(the member frame's variables are visible through bash's dynamic scoping) — a
bare `sandbox=0` in a callback silently disarms the default for the next run.

```bash
onLine() { local sandbox expr; …; }    # right: the names are the callback's own
```

---

## 5. CR, `binary`, `-z`, and the derived `-b` (owner Q5)

sed opens files in **text mode**: it strips the CR before the LF on input and
writes LF. So `crlf` is a no-op for the stream (as for tgrep), and:

| shape | what happens |
|---|---|
| default | `a1\r\n` arrives as the record `a1` |
| `binary = 1` | `-b`: the CR is kept (`a1\r`) |
| `binary = 1` + `crlf = 1` | exactly one trailing CR stripped per record (unless the script appends after `$`) |
| `inPlace = 1` | **derives `-b`**: in text mode `sed -i` would rewrite every CRLF to LF on disk, even with the identity script |
| `nullData = 1` | **derives `-b`** and the sinks' `-0`: in text mode `-z` strips a CR *inside* a NUL record (`x\r\ny` → `x\ny`) |

The derivation lives in `buildArgv` only — the `binary` property is never
written, so turning `inPlace`/`nullData` back off takes the `-b` away on the
next build, and a caller's own `binary = 1` is never touched. Consequence: the
wrapper has **no text-mode in-place path**. A caller who wants CRLF→LF on disk
says so in the script: `s/\r$//` (works under `-b`). On LF-only files `-b`
changes nothing.

`nullData = 1` derives `nul = 1` with tgrep's P3-F1 guard (`_nulDerived`): a
`nul = 1` the caller set is never cleared, and a refused build derives nothing.
An unterminated last NUL record stays unterminated, as does an unterminated
last line.

---

## 6. In-place (owner Q4) — `run` only

```bash
TSed.new s 's/old/new/' a.txt b.txt
s.inPlace = 1
s.backupSuffix = .bak                  # optional: a.txt.bak, b.txt.bak
s.run                                  # stdout is EMPTY; the files are edited
```

`inPlace = 1` → the five sinks answer **rc 2** with one line (*in-place editing
writes nothing to stdout; use run*), nothing runs, the files are byte-identical,
the caller's array is untouched and `lastRc` is untouched. The same refusal
applies to **`--debug`** among the extras, in any abbreviation down to `--d`
(*sed --debug writes to stdout; use run*): its `SED PROGRAM:` / `INPUT:` /
`PATTERN:` trace would arrive as records. `run` streams either. `-i` implies
`-s`. Setting `inPlace` back to 0 makes the same instance's sinks work again.

**`backupSuffix`** is attached to `-i` (one argv word; a space or a leading `-`
is harmless):

| suffix | backup |
|---|---|
| `.bak` | `FILE.bak` next to the file |
| `bak_*` | `*` is replaced by the **operand as given** — `bak_a.txt` for the bare operand `a.txt`, but `bak_DIR/a.txt` for `DIR/a.txt` (and `bak_/abs/…` for an absolute path): a directory that does not exist → **rc 1, `lastRc` 4, the file untouched**. Measured at P0 (the plan's first draft said "the base name", which holds only for an operand without a directory; PLAN §1.1 is corrected). Use it from the file's own directory |
| `bk/*` | a backup directory; a missing one is rc 1 / `lastRc` 4 with the file untouched |
| `*` | **rc 2** here — sed would make no backup at all, silently |

**Traps:**

* **`q`, `Q` and `quiet` without `p` truncate the file** under `inPlace`,
  silently and with rc 0: `inPlace` + `2q` leaves the first two lines on disk.
* An I/O error (raw 4) stops at that operand: `paths dir good.txt` leaves
  `good.txt` **unedited** (rc 1, `lastRc` 4).
* `--sandbox` does not protect in-place writes (§4).
* `inPlace` with no path, or with `-`, is rc 2 (§2).

---

## 7. `TSed.edit EXPR PATH...` — the one-liner

`sed --sandbox -e EXPR -- PATH...` as a **stream**, rc mapped. A `static proc`:
it prints sed's stdout and has no return channel.

```bash
TSed.edit 's/a/A/' f.txt                        # to the terminal
TSed.edit 's/a/A/' f.txt | TPipe.each cb        # lastpipe
TPipe.each cb -- TSed.edit 's/a/A/' f.txt       # the safe `--` form
```

All three deliver bytes identical to `sed --sandbox -e 's/a/A/' -- f.txt`.

* built on a throw-away instance `__tsd_e_${BASHPID}_${__TSD_SEQ}` with an
  EMPTY `expr` and then `addExpr "$EXPR"`, so **`TSed.edit '' f` is the
  identity** (a real `-e ''`), not "no script";
* the **sandbox is forced on**: `TSed.edit 's/x/y/e' f` is sed's rc 1, nothing
  runs;
* at least ONE path is required — with none sed would read the caller's stdin:
  rc 2, nothing runs, nothing read. Build an instance for the stdin form or for
  any option;
* a missing file is rc 1 with one line (sed's raw 2, mapped);
* the throw-away instance is deleted and `__TSD_SEQ` bumped once per call;
  nested `edit` from inside an outer sink's callback is safe (a unique name per
  call) and leaves the outer instance untouched.

---

## 8. The out-name registries

`__tsd_` is appended to `TUTIL_OUT_PREFIXES` and `_exprs` to the
`TUTIL_OUT_SUFFIXES` registry this unit introduced (tutil README §5): measured
before the fix, `s.toArray s_exprs` filled the instance's own expression list,
so the records became the **next** run's script (and with `sandbox = 0` a data
line `e …` a command). `s.argv s_exprs`, `s.toArray s_exprs`, `s.argv __tsd_v`,
`s.argv TUTIL_OUT_SUFFIXES` and `s.argv TUTIL_OUT_PREFIXES` are rc 2 with the
expression list intact; both appends are idempotent (re-sourcing the unit adds
nothing). The registry's own cases — its name refused, the fail-closed empty /
unset / scalar registry — live in `tutil/tests/001_Core.sh` §C.

---

## 9. Tests

```bash
bash kcl/tsed/tests/tests.sh                 # the whole suite
bash kcl/tsed/tests/tests.sh --mode single   # sequential, for a stack trace
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe kcl/tsed/tests/tests.sh
```

**293 checks, green on bash 5.2.37 and on bash 5.3.9**, in the default threaded
mode and (5.2.37) under `--mode single`, against GNU sed 4.9. Case by case:
[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md).

| file | checks | what | runs sed? |
|---|---|---|---|
| `004_Argv.sh` | 146 | S1–S5 by array comparison, sed never runs: lifecycle and both registries; every option singly and combined; the boolean-is-exactly-`1` rule and the fail-closed `sandbox` (eleven values); the rc 2 list incl. every deny-list spelling (short, bundled, attached, long, abbreviated, `=VALUE`), `--` in three positions, and the extras that pass; the `-0` four-state sequence and the derived `-b`; every option before the first `-e` | **no** |
| `005_Run.sh` | 70 | S5–S12 against bare sed on a fixture tree behind the banner gate: every sink, multi-`-e`, `-f`, `-n`, `-s`, the unterminated line, the identity, stdin, exotic names; partial / rc 4 / `q N`; the sandbox with marker files; CR and `-z` byte assertions (`od -c`); in-place on copies (backups, `bak_*` both shapes, the truncation trap, every sink refused, `--debug`); `TSed.edit` in three positions, nested, composed | yes (GNU banner gate first) |
| `006_Contract.sh` | 66 | S13: source integrity (incl. the rc-preserving overrides and no `-b` bookkeeping var), `set -eu` children through `s.each` and both TPipe forms with every sink call guarded, one debug line per rc 2 / sed-error path and silence on rc 0 and on a `q N` status, D6 + `subshellOk`, the unguarded-sink rule | yes (gated) |
| `007_Bench.sh` | 11 | the §10 gate as assertions with a **10×** ceiling behind the same banner gate: `TSed.edit` vs bare `sed --sandbox -e … --` over a 200-line and a one-line file (interleaved, medians, byte-identical outputs asserted), the edit delta under 50 ms, `s.count` vs `sed … \| wc -l`; 200 builds invoke the `cmd` zero times, fork nothing and do not accumulate; a refused (deny-list) build is the cheap path too; zero forks for every property, every builder member, `run`, `edit`, the five sinks' callback and `.Add`, and four rc 2 paths | yes (gated) |

The behavioural files open with a **GNU banner gate**: if `sed --version` does
not begin with `sed (GNU sed) `, every case below it is a loud `SKIP` rather
than a failure — D4 pins the dialect, not a binary, and the case **count is
unchanged**.

---

## 10. Performance

`bash kcl/tsed/bench.sh [NL] [NR] [ND]` — a generated corpus of a **10 000-line**
file and a **one-line** file (every line holds an `a`, so `s/a/A/` really
substitutes), both in a `mktemp -d` directory; NR = 21 **interleaved** runs per
gated shape, ND = 300 per-call measurements, timed with
`TStopwatch.getTimeStamp`. Measured **2026-09-23** on Windows 11 / MSYS2 with
the machine idle, against **GNU sed 4.9**:

| Measurement | bash 5.2.37 | bash 5.3.9 |
|---|---|---|
| `buildArgv` — the override (10 words, one extra scanned) | 1105.8 µs/call | 1170.7 µs/call |
| `argv NAME` (build + validate + copy) | 1979.8 µs/call | 2062.1 µs/call |
| `buildArgv` **refused** (rc 2, deny-list: `-ni` after `-u --posix`) | 1149.3 µs/call | 1210.5 µs/call |
| **`new` + `addExpr` + `sandbox` + `argv` + `delete`** — *the `edit` delta* | **5414.4 µs/call** | **5112.1 µs/call** |
| **baseline** — bare `sed --sandbox -e 's/a/A/' -- big.txt`, 10 000 lines (median of 21) | 37.20 ms | 36.44 ms |
| `TSed.edit 's/a/A/' big.txt` (median of 21) | 43.25 ms — **1.16×** | 43.23 ms — **1.18×** |
| **baseline** — bare `sed --sandbox -e 's/a/A/' -- one.txt`, 1 line (median of 21) | 33.67 ms | 31.08 ms |
| `TSed.edit 's/a/A/' one.txt` (median of 21) | 40.56 ms — **1.20×** | 38.78 ms — **1.24×** |
| worst **single** pairing inside those samples (big / one) | 8.49× / 12.31× | 9.12× / 9.34× |
| **baseline** — `sed --sandbox -e … -- big.txt \| wc -l` (median of 21) | 50.83 ms | 47.05 ms |
| `s.count` — 10 000 records into bash | 480.39 ms — **9.45×** | 482.30 ms — **10.24×** |
| the same sink over **one** record (its fixed half) | 38.70 ms | 38.21 ms |
| per record read into bash | ~44 µs | ~44 µs |
| forks per call | **1** (sed itself), **0** on a refused call | **1** / **0** |

Reading the table:

- **The gate is the four `TSed.edit` / baseline rows** ([PLAN.md](PLAN.md) §5
  P1): at most **1.5×** a bare `sed --sandbox -e … --` on the same file. Both
  shapes pass on both bashes. A second 5.2.37 run read **1.14×** and **1.18×** —
  the medians moved by two points while the means moved by up to 17 ms.
- **The delta is one throw-away instance.** The `new` + `addExpr` + `sandbox` +
  `argv` + `delete` row is what `edit` does around the fork: the constructor
  assigns **eleven** properties and declares **two** arrays (tfind's: nine and
  one, ~4.7 ms), and the build scans the extras against the deny-list. The gate
  rows' measured delta (6.1–7.7 ms) is a little more than that row, the rest
  being `run`'s own bookkeeping — the `command -v` probe and the `mapRc`
  dispatch — and the static call. It is a **per-call** cost, never a per-record
  one.
- **Corpus size is not the knob.** A whole `sed` run costs ~31–37 ms here (one
  msys process start plus the edit); the wrapper's fixed delta is ~5–7 ms. The
  ratio is therefore ~(35 + 6)/35 and can only *fall* as the file grows — which
  is why the 10 000-line file reads *lower* than the one-line file on both
  bashes, and why the one-line row (where the fork *is* the whole measurement)
  is the pessimistic one.
- **Medians, and why they are not negotiable.** Every timed number is one
  process start, and on this box a process start occasionally takes several
  hundred milliseconds for reasons outside this repo: the *means* beside these
  medians ran up to 2.2× them, and the **worst single pairing** inside these very
  samples read **8.5–12.3×**. tfind's planning pass saw the same effect at
  1.64× on code whose interleaved medians were 1.13–1.16×
  ([`../tfind/PLAN.md`](../tfind/PLAN.md) §8, finding 17). A one-shot comparison,
  or a non-interleaved loop, can therefore fail a 1.5× gate on code that is fine
  — so the two sides are timed one-of-each per iteration and the ratio is taken
  between medians. `bench.sh` prints the mean beside every median and the worst
  single pairing under every gate for exactly this reason.
- **The clock is `TStopwatch.getTimeStamp`, never `date +%s%N`.** On msys the
  latter is its own process at ~20 ms a call — more than half of the `sed` run
  being measured, and paid twice per sample.
- **`argv` runs nothing** and forks nothing: section (a) of the bench points
  `cmd` at a function that counts its own invocations and builds 600 times —
  the counter stays at 0 and `$BASHPID` never changes across 1 200 builds. The
  **rc 2** path is measured too (1149–1211 µs, the whole three-word deny-list
  scan inside it): a refused call does not even pay for the fork.
- **`count` is not the `wc -l` equivalent, and the ~10× row is why.** The sink
  reads every record into bash at ~44 µs a record; `wc -l` counts at memory
  speed in one more process. Over 10 000 records the pipeline wins by an order
  of magnitude — the sink's fixed half (one sed, ~38 ms) is *cheaper* than the
  pipeline's (~50 ms), so the crossover is near a couple of hundred records
  (`tests/007_Bench.sh` sees the sink slightly ahead at 200). That is why the
  row is **published, not gated** — and why, when all you want is the number
  over a big file, `sed … | wc -l` is the right answer.
- **Zero forks** (section (e)): `$BASHPID` is unchanged across 31 calls —
  twelve property writes, every builder member, the five sinks, `run`, `edit`,
  and three rc 2 paths (a deny-list hit, an in-place sink, a path-less `edit`)
  — and inside the `each` callback and a `.Add`.
- `tests/007_Bench.sh` asserts the same shapes with a ceiling of **10×**: under
  the threaded runner the two sides do not inflate together (sed is its own
  process; the wrapper's share is bash work in the contended shell).
