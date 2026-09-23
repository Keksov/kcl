# tsed — `TSed`, the GNU `sed` wrapper

> **Status: P0 (the unit) — first cut of this README.** `TSed : TUtil` — the
> class, the pinned argv, the rc 2 list with the owner's deny-list, the `mapRc`
> override, the five overridden sinks, `paths` / `addExpr` / `clearExprs`, the
> destructor and the static `TSed.edit` — plus the `TUTIL_OUT_SUFFIXES` registry
> this unit introduced in [`../tutil`](../tutil/README.md). Suite:
> `tests/004_Argv.sh` (146), `tests/005_Run.sh` (70), `tests/006_Contract.sh`
> (66) — **282 checks green on bash 5.2.37 and on 5.3.9**, threaded and (5.2.37)
> under `--mode single`, against **GNU sed 4.9** (5.2.37 resolves Git for
> Windows' `sed.exe`, 5.3.9 msys64's; both 4.9). P1 adds the bench, the final
> README and `TEST_COVERAGE_NOTES.md`. Design record: [PLAN.md](PLAN.md) (§2.0
> holds the six owner decisions Q1–Q6, §8 the critic pass) and
> [tsed_ledger.json](tsed_ledger.json). The base:
> [`../tutil/README.md`](../tutil/README.md); the siblings:
> [`../tgrep`](../tgrep/README.md), [`../thead`](../thead/README.md),
> [`../ttail`](../ttail/README.md), [`../tfind`](../tfind/README.md).

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
| `mapRc RAW` | func | — | override; §3 |
| `each` `toArray` `toList` `first` `count` | overrides | — | refuse `inPlace` / `--debug` (rc 2), else the base sink |
| `TSed.edit EXPR PATH...` | static proc | — | §7 |

Inherited from TUtil unchanged: `cmd` (`sed`), `crlf`, `nul`, `_lastRc`,
**`subshellOk`**, `addArg`, `clearArgs`, `argv NAME`, `run`, `lastRc`.
`subshellOk` is the D6-final switch: `s.subshellOk = 1` makes every sink pass
`-s` to `TPipe`, which silences the warning `$(s.toArray a)` otherwise prints.

A `var` is read as `$(s.expr)` and written as `s.expr = value`. A boolean is on
for the exact string **`1`** and off for anything else (`2`, `yes`, `true`,
`01`, `' 1'` are all off) — **except `sandbox`, which fails closed**: it is off
only for the exact string **`0`**, and every other value (`''`, `yes`, `2`,
`' 0'`, `00`, `false`) keeps `--sandbox`. That is a deliberate exception to the
family rule, because the sandbox is a security default (owner Q1, §4).

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
* `--` appears only with at least one path; with none sed reads stdin, and the
  path `-` is stdin explicitly.
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
| `inPlace = 1` with no path, or with the path `-` | sed cannot edit stdin in place |
| `backupSuffix` set with `inPlace = 0` | the suffix only means something to `-i` |
| `backupSuffix = '*'` | the backup name would equal the file's: **no backup, silently** |
| an extra on the **deny-list** (owner Q6, below) | it would duplicate a typed property or break the record stream |
| `--` among the extras | it ends sed's options before the first `-e`, so every expression would become an operand (`sed --sandbox -- -e s/a/A/ -- f`); the wrapper emits its own `--` before the paths |

No expression text is validated by the wrapper — sed compiles it (a bad
script is sed's rc 1).

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

The scan follows getopt, because getopt is what decides what sed does:

* a **bundle** is split: `-ni` is `-n -i`, `-us` contains `-s`; an argument
  attached to a short option is part of it — `-i.bak` is `-i`, `-es/a/b/` is
  `-e`, `-fscript` is `-f`;
* a long option is matched by **unambiguous prefix**, as getopt does — measured
  on sed 4.9, `--in=.bak` edits the file in place with rc 0, `--expr=p`,
  `--null` and `--sand` all work — and `--zero-terminated` is an undocumented
  alias of `-z`;
* `-l` is the one allowed option that takes an argument, so the scan stops
  there: `-l 40`, `-l40`, `-ul40` pass.

* a bare `--` word is refused too (see the rc 2 table above).

Everything else passes: `--posix`, `-u`/`--unbuffered`, `-l N`/`--line-length`,
`--follow-symlinks`, `--debug` (but see §6: the sinks refuse `--debug`).

### mapRc (owner Q3)

| raw | member | line of ours |
|---|---|---|
| `0` | 0 | — |
| `1` bad script, `2` a missing input file, `4` an I/O error | 1 | one: `sed exited N (a sed error, or the script's q/Q N)` |
| `127` | 1 | the base wording |
| anything else — a script's `q N` / `Q N` (N mod 256) | 1 | **none** — the raw value is in `lastRc` |

A script's `q1`, `q2` and `q4` cannot be told apart from sed's own codes; the
line is worded to say so. `q256` wraps to 0.

### Named deviations

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
`sed: -e expression #1, char 3: …`) — the tool's stream, locale-quoted, matched
by prefix in the tests. Exactly one line of ours accompanies it under the switch.

**(c) `sandbox = 1` by default** (owner Q1) — §4.

**(d) A script's `q N` / `Q N` status is not an error** — rc 1, silent, raw in
`lastRc` (above).

**(e) `inPlace` and `nullData` derive `-b`** (owner Q5) — §5.

### `$( )` loses the instance's state, and `set -e`

Under `$( )` every mutation is lost with the subshell: `$(s.run)` captures the
bytes but `_lastRc` is not updated. rc 1 is a normal answer here, so a `set -e`
script writes `s.count || rc=$?` (pinned in `tests/006_Contract.sh`).

---

## 3. Expressions

* `expr` is the constructor's first argument and the **first** `-e`; `''` means
  *none*.
* `addExpr EXPR...` appends; `clearExprs` empties the list (not `expr`).
* `scriptFile` adds `-f FILE` after all the expressions; a missing FILE is sed's
  **rc 4** (`couldn't open file`), no record at all.
* The identity is `addExpr ''` (`-e ''`), never `expr = ''`.

```bash
TSed.new s '2{' data.txt
s.addExpr 's/b/J/' '}'                 # sed --sandbox -e '2{' -e 's/b/J/' -e '}' -- data.txt
```

---

## 4. The sandbox (owner Q1)

`sandbox = 1` is the default: `--sandbox` makes sed refuse, **at compile time**,
every command that runs a program or touches a file other than stdout — `e`,
`s///e`, `r`, `R`, `w`, `W`, `s///w FILE`. It is total: a refused command in a
later `-e` or inside a `-f` script refuses the whole run (rc 1, sed's
*e/r/w commands disabled in sandbox mode*, no record, nothing executed or
written). Two consequences:

* the common idiom **`s/a/A/w /dev/stdout` is refused too — use `p`**;
* `--sandbox` limits the **script**, not in-place editing: `inPlace` still
  writes the file.

A caller who needs those commands says so: `s.sandbox = 0` — the exact string
`0` and nothing else. The property **fails closed**: `''`, `yes`, `2`, `' 0'`,
`00` all keep `--sandbox` (the one exception to the family's "on only for `1`"
boolean rule, §1). `TSed.edit` forces the sandbox and has no way to turn it off.

**Trap — callbacks declare `local`.** A callback that assigns a bare
`expr=`, `quiet=`, `inPlace=` or `sandbox=0` writes the **instance's** property
(the member frame's namerefs are visible through bash's dynamic scoping) — a
bare `sandbox=0` in a callback silently disarms the default for the next run.

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
says so in the script: `s/\r$//` (works under `-b`).

`nullData = 1` derives `nul = 1` with tgrep's P3-F1 guard (`_nulDerived`): a
`nul = 1` the caller set is never cleared. An unterminated last NUL record stays
unterminated, as does an unterminated last line.

---

## 6. In-place (owner Q4) — `run` only

```bash
TSed.new s 's/old/new/' a.txt b.txt
s.inPlace = 1
s.backupSuffix = .bak                  # optional: a.txt.bak, b.txt.bak
s.run                                  # stdout is EMPTY; the files are edited
```

`inPlace = 1` → the five sinks answer **rc 2** with one line (*in-place editing
writes nothing to stdout; use run*), nothing runs, the files are byte-identical
and `lastRc` is untouched. The same refusal applies to `--debug` among the
extras (*sed --debug writes to stdout; use run*): its trace would arrive as
records. `-i` implies `-s`.

**`backupSuffix`** is attached to `-i` (one argv word; a space or a leading `-`
is harmless):

| suffix | backup |
|---|---|
| `.bak` | `FILE.bak` next to the file |
| `bak_*` | `*` is replaced by the **operand as given** — `bak_a.txt` for the bare operand `a.txt`, but `bak_DIR/a.txt` for `DIR/a.txt` (and `bak_/abs/…` for an absolute path): a directory that does not exist → **rc 1, `lastRc` 4, the file untouched**. *Measured at P0; PLAN §1.1 said "the base name", which holds only for an operand without a directory.* Use it from the file's own directory |
| `bk/*` | a backup directory; a missing one is rc 4 with the file untouched |
| `*` | **rc 2** here — sed would make no backup at all, silently |

**Traps:**

* **`q`, `Q` and `quiet` without `p` truncate the file** under `inPlace`,
  silently and with rc 0: `inPlace` + `2q` leaves the first two lines on disk.
* An I/O error (raw 4) stops at that operand: `paths dir good.txt` leaves
  `good.txt` **unedited** (rc 1, `lastRc` 4).
* `--sandbox` does not protect in-place writes (§4).

---

## 7. `TSed.edit EXPR PATH...` — the one-liner

`sed --sandbox -e EXPR -- PATH...` as a **stream**, rc mapped. A `static proc`:
it prints sed's stdout and has no return channel.

```bash
TSed.edit 's/a/A/' f.txt                        # to the terminal
TSed.edit 's/a/A/' f.txt | TPipe.each cb        # lastpipe
TPipe.each cb -- TSed.edit 's/a/A/' f.txt       # the safe `--` form
```

* built on a throw-away instance `__tsd_e_${BASHPID}_${__TSD_SEQ}` with an
  EMPTY `expr` and then `addExpr "$EXPR"`, so **`TSed.edit '' f` is the
  identity** (a real `-e ''`), not "no script";
* the sandbox is forced on;
* at least ONE path is required — with none sed would read the caller's stdin:
  rc 2, nothing runs. Build an instance for the stdin form or for any option;
* nested `edit` from inside an outer sink's callback is safe (a unique name per
  call).

---

## 8. The out-name registries

`__tsd_` is appended to `TUTIL_OUT_PREFIXES` and `_exprs` to the
`TUTIL_OUT_SUFFIXES` registry this unit introduced (tutil README §5): measured
before the fix, `s.toArray s_exprs` filled the instance's own expression list,
so the records became the **next** run's script (and with `sandbox = 0` a data
line `e …` a command). `s.argv s_exprs`, `s.toArray s_exprs`, `s.argv __tsd_v`
and `s.argv TUTIL_OUT_SUFFIXES` are rc 2; both appends are idempotent.

---

## 9. Tests

| file | checks | what |
|---|---|---|
| `004_Argv.sh` | 146 | S1–S5 by array comparison, sed never runs: lifecycle and both registries; every option singly and combined; the rc 2 list incl. every deny-list spelling and the extras that pass; the `-0` four-state sequence and the derived `-b`; every option before the first `-e` |
| `005_Run.sh` | 70 | S5–S12 against bare sed on a fixture tree behind the banner gate: every sink, multi-`-e`, `-f`, `-n`, `-s`, the unterminated line, the identity, stdin; partial/rc 4/`q N`; the sandbox with marker files; CR and `-z` byte assertions (`od -c`); in-place on copies; `TSed.edit` in three positions, nested, composed |
| `006_Contract.sh` | 66 | S13: source integrity (incl. the rc-preserving overrides), `set -eu` children through `s.each` and both TPipe forms with every sink call guarded, one debug line per rc 2 / sed-error path and silence on rc 0 and on a `q N` status, D6 + `subshellOk` |
