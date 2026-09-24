# tawk — `TAwk`, the GNU Awk wrapper

> **Status: COMPLETE (P0 + P1).** `TAwk : TUtil` is the whole unit — the
> class, the pinned argv, the rc 2 list with the getopt-aware deny-list (`-W`
> spellings included), the verbatim `setVar`, the `mapRc` override, the five
> overridden sinks, `paths` / `addProgram` / `clearPrograms` / `setVar` /
> `clearVars`, the destructor, the static `TAwk.apply`, the bench and the docs.
> Suite: `tests/004_Argv.sh` (396), `tests/005_Run.sh` (105),
> `tests/006_Contract.sh` (79), `tests/007_Bench.sh` (12) — **592 checks green
> on bash 5.2.37 and 592 on bash 5.3.9** (580 from P0 + 12 from P1), threaded
> and (5.2.37) under `--mode single`. **Two gawk versions:** bash 5.2.37
> resolves Git for Windows' `/usr/bin/gawk` = **GNU Awk 5.0.0**, bash 5.3.9
> msys64's = **GNU Awk 5.4.0** (§0); the behavioural tests pin behaviour on both
> and match gawk's own messages by prefix. What the tests pin, case by case:
> **[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md)**. Design record:
> [PLAN.md](PLAN.md) (§2.0 holds the four owner decisions, §8 the critic pass)
> and [tawk_ledger.json](tawk_ledger.json). The base:
> [`../tutil/README.md`](../tutil/README.md); the closest sibling:
> [`../tsed`](../tsed/README.md); the others:
> [`../tgrep`](../tgrep/README.md), [`../thead`](../thead/README.md),
> [`../ttail`](../ttail/README.md), [`../tfind`](../tfind/README.md).
>
> **What the critic pass and the P0 review changed**, and what the tests pin:
> the first draft's `env` + `ENVIRON` route for `setVar` was dropped — **`-v`
> round-trips every byte once the value is encoded** (§3; the probe that said
> otherwise had been corrupted by a tool collapsing `\\`); an **empty chunk is
> never emitted** (gawk drops `-e ''` and compiles the first path as the
> program); the deny-list follows gawk's getopt, **`-W long-option` spellings
> and any long-option prefix included**; the inplace extension is loaded by its
> **absolute path** (a planted `./inplace.awk` ran with the sandbox off); and,
> at the P0 review, **`backupSuffix` is encoded like `setVar`** (§6).

`TAwk` is a [`TUtil`](../tutil/README.md) descendant: typed properties instead
of a hand-built command string, one rc convention, and the five `TPipe` sinks.

```bash
source kcl/tawk/tawk.sh

TAwk.apply '{print $2}' data.txt       # the one-liner: `gawk --sandbox -e PROGRAM -- data.txt`

TAwk.new a '{print $1}' in.txt         # or an instance, for options
a.fieldSep = :                         # -F :
a.setVar pat 'C:\dir\n'                # VERBATIM — the program sees exactly these bytes
a.addProgram 'END{print NR}'           # more chunks, emitted in call order
a.toArray lines                        # RESULT = ${#lines[@]}
a.each r.onLine                        # one call per record, THIS shell
a.lastRc                               # RESULT = gawk's RAW exit status

a.sandbox = 0                          # in-place needs the sandbox off
a.inPlace = 1                          # `run` only, the sinks refuse
a.backupSuffix = .bak
a.run
a.delete
```

---

## 0. The four owner decisions (PLAN §2.0)

| Q | decision | where |
|---|---|---|
| **Q1** sandbox | `sandbox = 1` by default and **fail-closed**: `--sandbox` is omitted only when `sandbox` is exactly `0` | §4 |
| **Q2** variables | `setVar NAME VALUE` is **verbatim**: emitted as `-v NAME=enc(VALUE)` (every `\` doubled, every newline `\n`, a leading `@` `\100`), byte-exact on both gawk versions. Awk-escape semantics stay available through `addArg -v NAME=VALUE` | §3 |
| **Q3** model and rc | as TSed: `var program` + `addProgram`/`clearPrograms` + `programFile`; rc 1/2 → 1 + one debug line worded *gawk exited N (a gawk error, or the program's exit N)*, any other status → 1 silent, raw in `lastRc`; a deny-list for `addArg` | §2 |
| **Q4** in-place | as TSed: `inPlace` + `backupSuffix`, `run` only, the five sinks overridden (rc 2), `inPlace` derives `BINMODE=3`; it additionally **requires `sandbox = 0`** — the sandbox refuses the inplace extension | §6 |

### The two gawk versions (D4: the dialect, not a binary)

| | bash 5.2.37 | bash 5.3.9 |
|---|---|---|
| `gawk` resolved | Git for Windows' `/usr/bin/gawk` — **GNU Awk 5.0.0** | msys64's `/usr/bin/gawk` — **GNU Awk 5.4.0** |
| message texts | differ between the two — the tests match `gawk: ` by prefix | |
| the directory warning | identical on both (pinned exactly, 005 §C) | |
| `INPLACE_SUFFIX` | does not exist — hence `inplace::suffix` | exists; `inplace::suffix` works too |
| long-option abbreviations | `--t`, `--tr` are `--traditional` | `--t` ambiguous — the deny-list refuses **any** prefix, never per version |
| `-I`/`--trace`, `-k`/`--csv` | unknown (gawk's own error) | exist; pass the deny-list |
| `mkbool` | not a builtin | a builtin — `setVar mkbool` is refused on both |
| sandbox | refuses `system()`, redirections, pipes, extensions | also refuses `ARGV[ARGC++]=…`; with `-M` blanks `ARGV[1]` and reads stdin (so `-M` is denied) |
| `-v 'x=\u0041'` (bare) | a warning, the backslash dropped | decoded to `A` — `setVar` gives the six bytes on both (§3) |

Behaviour the wrapper relies on is identical on both and pinned on both. Run
5.3.9 with msys64's `/usr/bin` first on `PATH` (§9); launching msys64's gawk
from Git's bash crosses two msys runtimes and mangles `{…}` and `''` arguments.

---

## 1. Surface

```bash
TAwk.new INST [PROGRAM [PATH...]]      # PROGRAM -> program, the rest are paths
```

| Member | Kind | Flag | Notes |
|---|---|---|---|
| `program` | var | `-e PROGRAM` | the **first** chunk; `''` = none |
| `addProgram CHUNK...` | proc | `-e X` each | appended after `program`, in call order; an **empty** chunk is stored but **never emitted** |
| `clearPrograms` | proc | — | empties the list; `program` is left alone |
| `programFile` | var | `-f FILE` | `''` = off; emitted **after** every chunk; `-` is rc 2; resolved through AWKPATH (deviation (h)) |
| `fieldSep` | var | `-F FS` | `''` = off; awk semantics — a regex, escapes processed (`'\t'` is a TAB) |
| `setVar NAME VALUE` | proc | `-v NAME=enc(VALUE)` | **verbatim** (§3); a repeated NAME replaces its value in place |
| `clearVars` | proc | — | forgets every pair |
| `nullData` | var | `-v RS='\0' -v ORS='\0'` | NUL records; **derives** the sinks' `-0` and `BINMODE=3` (§5) |
| `binary` | var | `-v BINMODE=3` | keep the CR (§5); also derived, never written by the wrapper |
| `sandbox` | var | `--sandbox` | **default 1**, **fails closed** — off only for the exact string `0` (§4) |
| `inPlace` | var | `-i /usr/share/awk/inplace.awk` | requires `sandbox = 0`; derives `BINMODE=3`; the five sinks refuse it (§6) |
| `backupSuffix` | var | `-v inplace::suffix=enc(SFX)` | only with `inPlace = 1`; **verbatim** — encoded like `setVar` (§6) |
| `paths PATH...` | proc | `-- PATH...` | **replaces** the operand list; no argument = stdin |
| `buildArgv` | func | — | override; fills `${inst}_argv`, RESULT = word count |
| `mapRc RAW` | func | — | override; §2 |
| `each` `toArray` `toList` `first` `count` | overrides | — | refuse `inPlace` (rc 2), else the base sink |
| `TAwk.apply PROGRAM PATH...` | static proc | — | §7 |

Inherited from TUtil unchanged: `cmd` (`gawk`), `crlf`, `nul`, `_lastRc`,
**`subshellOk`**, `addArg`, `clearArgs`, `argv NAME`, `run`, `lastRc`.

**`subshellOk` (D6 final)** is inherited, default `0`: `a.subshellOk = 1` makes
every sink pass `-s` to `TPipe`, which silences the warning `$(a.toArray x)`
otherwise prints (*Warning: TPipe.toArray: the array x is filled inside a
subshell …*) — the array is filled in the subshell and lost with it either way.

A boolean is on for the exact string **`1`** (`2`, `yes`, `true`, `01`, `' 1'`
are off) — **except `sandbox`**, which is off only for the exact string **`0`**
(`''`, `yes`, `2`, `' 0'`, `00`, `-0`, `false`, `off` all keep `--sandbox`).

### The argv, pinned

```
gawk [--sandbox] [-F FS] [-v RS=\0 -v ORS=\0] [-v BINMODE=3]
     [-i /usr/share/awk/inplace.awk [-v inplace::suffix=enc(SFX)]]
     [EXTRA OPTIONS from addArg] [-v NAME=enc(VALUE) ...]
     [-e program] [-e chunk ...] [-f FILE] [-- PATH...]
```

* gawk concatenates `-e` and `-f` sources **in argument order**; so `program`
  runs before the chunks, and both before `programFile`.
* **Each `-e` chunk must be a complete source**: gawk compiles every chunk on
  its own (`-e 'BEGIN{' -e 'print 1}'` is rc 1, and `@namespace` resets per
  chunk). A block cannot span chunks — unlike sed.
* An **empty chunk is never emitted**: gawk drops `-e ''` with a warning, and if
  nothing else is left it compiles the first path as THE program (a path named
  `1` is a valid program that reads stdin). No program at all is rc 2.
* The `setVar` words come **after** the extras, so they win over an
  `addArg -v NAME=…` of the same name; they keep insertion order.
* `BINMODE=3` appears **once**, when `binary` **or** `inPlace` **or**
  `nullData` is 1 (§5).
* The inplace extension is loaded by its **absolute** path (§6).
* `--` appears only with at least one path; with none gawk reads stdin, and the
  path `-` is stdin explicitly.
* An **empty path** `''` is passed through as an operand, as the bare tool
  would get it: gawk skips an empty operand (rc 0) and reads the other paths —
  tool parity, not refused by the wrapper.

`a.argv NAME` builds the array and **runs nothing** — that is how
`tests/004_Argv.sh` pins every option without executing gawk.

---

## 2. Return contract

`rc 0` = gawk did everything asked. `rc 1` = it did not (or the program chose a
non-zero exit). `rc 2` = the **call** was malformed and nothing ran. The raw
status stays readable through `lastRc`.

### The rc 2 list — a malformed call, and nothing runs

`buildArgv` answers **rc 2** with `RESULT=''`, one `kk.debug` line naming the
reason, and `${inst}_argv` left empty; every runner passes the 2 straight back
and `lastRc` stays `-1` on a fresh instance.

| refusal | why |
|---|---|
| `cmd` is empty | the instance was disarmed by hand |
| **no program** — `program` `''`, every chunk `''`, `programFile` `''` | gawk would take the first path **as the program** (and may read stdin) |
| `programFile = -` | gawk would read the program from stdin |
| a path gawk reads as an **assignment** — `^([A-Za-z_][A-Za-z0-9_]*::)?[A-Za-z_][A-Za-z0-9_]*=` (`k=v`, `a::b=v`, `awk::x=v`, `_x=`) | gawk assigns it instead of reading it; the line names the `./k=v` spelling. `1x=v`, `é=v`, `x.y=v`, `C:/x=y`, `./k=v` and absolute paths are files and pass |
| `inPlace = 1` with no path, or with `-` anywhere | gawk cannot edit stdin in place |
| **`inPlace = 1` with `sandbox` ≠ `0`** | the sandbox refuses the inplace extension |
| `backupSuffix` set with `inPlace = 0` | the suffix only means something to in-place editing |
| a stored variable name gawk would reject | `setVar` refuses it already; `${inst}_vnames` is a global, so the build checks again |
| an extra on the **deny-list**, `--`, a non-option word, a dangling argument-taking option | below |

`setVar` itself answers rc 2 (one line, nothing stored) for a NAME that is not
an awk identifier (`''`, `1x`, `x.y`, `a b`, `a::b`, `é`), for an awk keyword
(`BEGIN END BEGINFILE ENDFILE function func if else while for do break continue
next nextfile exit return delete getline print printf in switch case default`),
for every builtin function of gawk 5.4 (incl. `mkbool`, which 5.0 does not
know), for `ENVIRON PROCINFO SYMTAB FUNCTAB`, and for a call with other than two
arguments. gawk itself stops with a fatal rc 2 on every one of those names.

No program text is validated by the wrapper — gawk compiles it (a syntax error
is gawk's rc 1).

### The deny-list (Q3), following gawk's getopt

An `addArg` word that gawk reads as one of these options is rc 2; the line
names the option by its long name and says why:

| option | why |
|---|---|
| `-e` `--source` | the program — use `program` / `addProgram` |
| `-f` `--file` | use `programFile` |
| `-i` `--include` | loads through AWKPATH — in-place is `inPlace` |
| `-l` `--load` | loads a binary extension |
| `-E` `--exec` | ends the options, takes the program from a file |
| `-F` `--field-separator` | use `fieldSep` |
| `-S` `--sandbox` | use `sandbox` |
| `-o` `--pretty-print`, `-g` `--gen-pot` | do not run the program (and `-o` writes a file) |
| `-h` `--help` `--usage`, `-V` `--version`, `-C` `--copyright` | print to stdout, do not run the program |
| `-d` `--dump-variables`, `-p` `--profile` | write files, **even under the sandbox** |
| `-D` `--debug` | reads debugger commands from stdin — hangs |
| `-M` `--bignum` | on 5.4 with the sandbox, blanks `ARGV[1]` and reads stdin |
| `-P` `--posix`, `-c` `--traditional` — **only while binary mode is derived** (`binary`, `nullData` or `inPlace`) | they silently disable `BINMODE` |

The scan follows getopt on BOTH versions:

* a long option matches by **any prefix**, and the two versions disagree on
  ambiguity (`--t` is `--traditional` on 5.0, ambiguous on 5.4), so a NAME that
  is a prefix of a denied option is refused, never decided per version —
  `--so`, `--sa`, `--s`, `--f`, `--l`, `--p`, `--u`, `--v`, `--d`, `--b`,
  `--=x` are all rc 2 (`--lint`, `--ch`, `--n…`, `--use-lc-numeric` pass);
* **`-W long-option`** is a second spelling of every long option — attached or
  separate, abbreviable, in a bundle: `-W so=P`, `-Wsource=P`, `-W s`, `-Wv`,
  `-bW source=P` are refused like `--source`;
* a short **bundle** is split: each letter is an option until one that takes an
  argument (`-bS`, `-nM`, `-bo` are refused; in `-vx=1` and `-Lfatal` the rest
  of the word is the argument and is not scanned);
* **`--`** among the extras is rc 2 — it ends gawk's options, and every chunk
  after it would become an operand;
* a word that is **not an option** (incl. `''` and a bare `-`) is rc 2 — gawk
  stops parsing at it and takes it as THE program;
* an argument-taking option (`-v`, `--assign`/`--as`, `-W`, `-W assign`) as the
  **last** extra is rc 2 — it would swallow the first word the wrapper
  generates; a word consumed as an argument (`-v e=-S`) is not scanned.

Everything else passes: `-v NAME=…` / `--assign` (the escape hatch of Q2),
`--lint[=…]`, `-L…`, `-t`, `-n`, `-N`, `-O`, `-s`, `-r`, `-b`, `--nostalgia`,
`--optimize`, `--trace`/`-I` and `--csv`/`-k` (5.4 only — gawk 5.0 rejects
them itself), and `-P`/`-c` while binary mode is not derived.

### mapRc (owner Q3)

| raw | member | line of ours |
|---|---|---|
| `0` | 0 | — |
| `1` syntax error / fatal runtime error; `2` a missing input or `-f` file, a sandbox refusal, an illegal `-v` | 1 | one: `gawk exited N (a gawk error, or the program's exit N)` |
| `127` | 1 | the base wording |
| anything else — a program's `exit N` (N mod 256: `exit 300` → 44, `exit -1` → 255) | 1 | **none** — the raw value is in `lastRc` |

A program's `exit 1` / `exit 2` cannot be told apart from gawk's own codes; the
line is worded to say so. `exit 256` wraps to 0 and is rc 0.

### The named deviations (PLAN §2.6)

**(a) A missing input file is FATAL, and a directory is skipped.** gawk
processes the files **before** a missing one and never reads the files after
it (unlike sed's rc 2, like its rc 4). The family contract per sink, pinned in
005 §C:

| sink | a missing file in the middle |
|---|---|
| `count` / `toArray` / `toList` | rc 1, RESULT = the earlier files' records |
| `each` | rc 1, those records delivered, RESULT untouched (a proc) |
| `first` | rc 0, the first record, `lastRc` 2, **no** line of ours (TUtil's consumer-stop rule); if the missing file is first: rc 1, no record |

A directory operand is skipped with ``gawk: cmd. line:1: warning: command line
argument `DIR' is a directory: skipped`` (identical on 5.0 and 5.4), the later
files are read, rc 0.

**(b) gawk's own stderr passes through unconditionally** — the tool's stream,
its texts differ between 5.0 and 5.4. Exactly one line of ours accompanies an
error under the switch.

**(c) `sandbox = 1` by default, and it fails closed** (owner Q1) — §4. It
refuses more than a user of plain `awk` expects: `print > "/dev/stderr"`, input
redirection and `|&` too.

**(d) A program's `exit N` is not an error** — rc 1, silent, raw in `lastRc`
(`exit 1` / `exit 2` get the debug line, worded to say so).

**(e) `inPlace` and `nullData` derive `BINMODE=3`** — §5.

**(f) `setVar` is verbatim**, unlike `-v` — §3.

**(g) `print` terminates an unterminated last line** (it appends ORS): the
records are the same, the byte stream gains one newline (or one NUL under
`nullData`).

**(h) `programFile` is resolved through AWKPATH** (`-f getopt.awk` silently
loads `/usr/share/awk/getopt.awk`); `-` is refused.

Two more are the family's, inherited from [tutil](../tutil/README.md): `run`
**streams** to stdout by definition, and for the counting sinks rc 1 means the
tool exited non-zero while `RESULT` still carries the count.

### `$( )` loses the instance's state, and `set -e`

Under `$( )` every mutation is lost with the subshell: `$(a.run)` captures the
bytes but `_lastRc` is not updated. rc 1 is a normal answer here, so a `set -e`
script writes `a.count || rc=$?` — an unguarded sink call with rc 1 aborts the
caller (pinned in `tests/006_Contract.sh`).

---

## 3. Variables — `setVar` is verbatim (owner Q2)

**Why `-v` alone is not verbatim.** `-v NAME=VALUE` processes awk escape
sequences in VALUE: `\t` becomes a TAB, `\\` one backslash, `\n` a newline, an
unknown `\k` becomes `k` with a warning, and `\u0041` is decoded to `A` on
5.4 while 5.0 warns and drops the backslash — the two versions do not even agree
(pinned against the bare tool in 005 §B). A value beginning `@/…/` becomes a
typed regexp, not a string. So a Windows path, a regex or any caller data passed
through plain `-v` arrives changed. The first draft routed values through
`ENVIRON` for that reason; the critic pass measured that `-v` DOES round-trip
every byte once the value is **encoded** (and the env route cost +13–25 ms per
run), so `setVar` stores the caller's bytes and `buildArgv` emits
`-v NAME=enc(VALUE)`:

| byte in VALUE | written as |
|---|---|
| `\` | `\\` |
| newline | `\n` |
| a **leading** `@` | `\100` |

gawk's escape processing then gives back exactly VALUE — measured byte-exact
(`od -c`) on 5.0 and 5.4 through `run` and a sink over: `\t` as two bytes, `\\`,
a trailing `\`, `\` + newline, `$'"`, UTF-8, `@/foo/`, a lone `@`, a CR, the
byte `\377`, `\u0041` as text, `/c/foo` (no msys path conversion), ` 010 `
(`typeof` stays `strnum`), a newline, the empty value, `&amp&`. The stored
value in `${inst}_vvals` is the caller's, unencoded.

* the variables keep **insertion order** (indexed `${inst}_vnames` /
  `${inst}_vvals`); a repeated NAME replaces its value **in its slot**;
* `setVar` wins over an `addArg -v` of the same name (it is emitted after the
  extras);
* for awk-escape semantics use the hatch: `a.addArg -v 'x=a\tb'` is a TAB.

`${inst}_progs`, `${inst}_vnames` and `${inst}_vvals` are the unit's own
storage and are on the out-name registry (§8).

---

## 4. The sandbox (owner Q1)

`sandbox = 1` is the default. `--sandbox` makes gawk refuse, with a **fatal**
error (gawk's rc 2 → member rc 1, nothing executed or written — the tests prove
it with marker files):

| refused | |
|---|---|
| `system()` | also inside an `@include`d file |
| output redirection `>`, `>>`, **including `> "/dev/stderr"` and `> "/dev/stdout"`** | |
| `\| CMD`, `"CMD" \| getline`, the coprocess `\|&` | |
| **input** redirection `getline < FILE` | |
| extensions — `-l`, `@load`, and `-i inplace` | hence `inPlace` requires `sandbox = 0` |
| on 5.4, adding files to `ARGV` at run time | |

`@include "file"` is allowed (and its `system()` still refused). `-d`, `-p` and
`-o` write files even under the sandbox — they are on the deny-list.

A caller who needs those says so: `a.sandbox = 0` — the exact string `0` and
nothing else. `TAwk.apply` forces the sandbox.

**Trap — callbacks declare `local`.** A callback that assigns a bare
`program=`, `programFile=`, `inPlace=` or `sandbox=0` writes the **instance's**
property (the member frame's variables are visible through bash's dynamic
scoping) — a bare `sandbox=0` in a callback silently disarms the default for the
next run (measured: `system()` ran on the next `run`).

```bash
onLine() { local sandbox program; …; }   # right: the names are the callback's own
```

---

## 5. CR, `binary`, NUL records, and the derived `BINMODE=3`

gawk opens its input in **text mode**: it strips the CR before the LF on file
and stdin input, and never writes CRLF. So `crlf` is a no-op for the stream, and:

| shape | what happens |
|---|---|
| default | `a 1\r\n` arrives as the record `a 1` |
| `binary = 1` | `-v BINMODE=3`: the CR is kept (`a 1\r`) |
| `binary = 1` + `crlf = 1` | exactly one trailing CR stripped per record |
| `inPlace = 1` | **derives `BINMODE=3`**: in text mode the in-place rewrite would turn every CRLF into LF on disk |
| `nullData = 1` | **derives `BINMODE=3`** and the sinks' `-0`: in text mode a CR *inside* a NUL record is lost (`x\r\ny` → `x\ny`) |

The derivation lives in `buildArgv` only; the `binary` property is never
written, so turning `inPlace`/`nullData` off takes `BINMODE` away again and a
caller's own `binary = 1` is never touched. `--posix`/`-P` and
`--traditional`/`-c` silently disable `BINMODE`, so they are refused while it
is derived.

`nullData = 1` emits `-v RS='\0' -v ORS='\0'` (both are needed for NUL output)
and derives `nul = 1` with tgrep's P3-F1 guard (`_nulDerived`): a `nul = 1` the
caller set is never cleared, and a refused build derives nothing. An
unterminated last NUL record comes out **terminated** (deviation (g)).

---

## 6. In-place (owner Q4) — `run` only

```bash
TAwk.new a '{gsub(/old/, "new"); print}' a.txt b.txt
a.sandbox = 0                          # required: the sandbox refuses the extension
a.inPlace = 1
a.backupSuffix = .bak                  # optional: a.txt.bak, b.txt.bak
a.run                                  # the files are edited; see the traps for stdout
```

* The extension is loaded as `-i /usr/share/awk/inplace.awk` — an **absolute**
  path. `-i inplace` is resolved through AWKPATH (`.:/usr/share/awk` by
  default), so a planted `./inplace.awk` in the current directory would load
  instead, and run with the sandbox off (measured; pinned in 005 §G against the
  bare tool).
* `backupSuffix` is `-v inplace::suffix=enc(SFX)` — it works on 5.0 and 5.4
  (`INPLACE_SUFFIX` exists on 5.4 only). The suffix is **verbatim**: it goes
  through the same encoding as `setVar` (§3), because `-v` escape-processes
  its value — unencoded, `.b\k` would become `.bk` with a warning. Note that on
  msys a `\` in a path is a directory separator: `.b\k` names the backup
  `FILE.b\k` = `FILE.b/k`, which needs the directory `FILE.b` (without it gawk's
  `link()` fails: rc 1, `lastRc` 2, the file untouched) — pinned in 005 §G.
* `inPlace = 1` → the five sinks answer **rc 2** with one line (*in-place
  editing writes nothing to stdout; use run*), nothing runs, the files and the
  caller's array are untouched, `lastRc` is untouched. Setting `inPlace` back
  to 0 makes the same instance's sinks work again.
* `inPlace = 1` with the sandbox on, with no path or with `-` is rc 2 (§2).

**Traps** (gawk's, documented, some pinned):

* **END output goes to stdout**, not into a file; ENDFILE output goes into the
  file.
* **`exit` mid-file truncates that file** and leaves the later files untouched
  (rc 0).
* **A missing file stops there**: the earlier files are edited, the later ones
  never touched (rc 1, `lastRc` 2).
* A fatal runtime error leaves the current file untouched.
* The wrapper has no text-mode in-place path (BINMODE is derived); a caller who
  wants CRLF→LF on disk says so in the program: `{sub(/\r$/, ""); print}`.

---

## 7. `TAwk.apply PROGRAM PATH...` — the one-liner

`gawk --sandbox -e PROGRAM -- PATH...` as a **stream**, rc mapped. A
`static proc`: it prints gawk's stdout and has no return channel.

```bash
TAwk.apply '{print $2}' f.txt                        # to the terminal
TAwk.apply '{print $2}' f.txt | TPipe.each cb        # lastpipe
TPipe.each cb -- TAwk.apply '{print $2}' f.txt       # the safe `--` form
```

All three deliver bytes identical to `gawk --sandbox -e '{print $2}' -- f.txt`.

* an **empty PROGRAM is rc 2** — gawk would drop `-e ''` and compile the first
  path as the program;
* at least ONE path is required — with none gawk would read the caller's stdin:
  rc 2, nothing runs, nothing read;
* an assignment-looking path (`k=v`) is rc 2 (use `./k=v`);
* the **sandbox is forced on**: `TAwk.apply 'BEGIN{system("…")}' f` is rc 1,
  nothing runs;
* a missing file is rc 1 with one line (gawk's raw 2, mapped);
* built on a throw-away instance `__taw_a_${BASHPID}_${__TAW_SEQ}`, deleted
  after the run; a nested `apply` inside an outer sink's callback is safe and
  leaves the outer instance untouched.

---

## 8. The out-name registries

`__taw_` is appended to `TUTIL_OUT_PREFIXES`, and `_progs`, `_vnames`, `_vvals`
to `TUTIL_OUT_SUFFIXES` (tutil README §5), each only if absent: `a.argv a_progs`
or `a.toArray a_vnames` would otherwise hand the caller the instance's own
storage and turn the records into the next run's program or variables.
`a.argv __taw_v`, `a.toArray a_progs`, `a.argv a_vvals` and the registries' own
names are rc 2 with the lists intact; re-sourcing the unit adds nothing.

---

## 9. Tests

```bash
bash kcl/tawk/tests/tests.sh                 # the whole suite
bash kcl/tawk/tests/tests.sh --mode single   # sequential, for a stack trace
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe kcl/tawk/tests/tests.sh
```

**592 checks, green on bash 5.2.37 (gawk 5.0.0) and on bash 5.3.9 (gawk
5.4.0)**, in the default threaded mode and (5.2.37) under `--mode single`. Case
by case: [TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md).

| file | checks | what | runs gawk? |
|---|---|---|---|
| `004_Argv.sh` | 396 | A1–A4 by array comparison: lifecycle and both registries; every option singly and combined; chunks (empty never emitted); setVar order, in-place replacement and the encoding; the boolean rule and the fail-closed sandbox; the rc 2 list incl. every deny-list spelling (short, attached, bundled, long, any prefix, `-W` in four shapes), the BINMODE-disabling options while derived, `--`, non-option words, dangling options, the extras that pass; every illegal `setVar` name; the `-0` four-state sequence and the derived BINMODE | **no** |
| `005_Run.sh` | 105 | A5–A12 against bare gawk on a fixture tree behind the banner gate, stdin closed: every sink, chunks in order, `-f` after `-e`, `-F` (escape, regex), the terminated last line, stdin, `./k=v` / `a::b=v` files; the setVar byte matrix (`od -c`, `run` and a sink); the fatal missing file per sink, syntax error, `exit N`, the directory warning; the sandbox with marker files; CR and NUL bytes; in-place on copies (the planted `./inplace.awk`, `.bak`, a backslash suffix (encoded, both versions), a missing middle file, `exit` truncation, END to stdout, every sink refused); `TAwk.apply` in three positions, nested, composed | yes (GNU banner gate first) |
| `006_Contract.sh` | 79 | A13: source integrity (rc-preserving overrides, the absolute include, no env route), `set -eu` children through `a.each` and both TPipe forms with every sink call guarded, one debug line per rc 2 / gawk-error path and silence on rc 0 and on an `exit N` status, D6 + `subshellOk`, the unguarded-sink rule | yes (gated) |
| `007_Bench.sh` | 12 | the §10 gate as assertions with a **10×** ceiling behind the same banner gate: `TAwk.apply` vs bare `gawk --sandbox -e … --` over a 200-line and a one-line file (interleaved, medians, byte-identical outputs asserted), the `apply` delta under 50 ms, `a.count` vs `gawk … \| wc -l`; 200 builds invoke the `cmd` zero times, fork nothing and do not accumulate; a refused (`-W` deny-list) build is the cheap path too; the 1 KiB `setVar` encoding is fork-free; zero forks for every property, every builder member, `run`, `apply`, the five sinks' callback and `.Add`, and five rc 2 paths | yes (gated) |

The behavioural files open with a **GNU banner gate**: if `gawk --version` does
not begin with `GNU Awk `, every behavioural case is a loud `SKIP` and the case
count is unchanged.

---

## 10. Performance

`bash kcl/tawk/bench.sh [NL] [NR] [ND]` — a generated corpus of a **10 000-line**
file and a **one-line** file (every line `aNNNNN xyz`, so `{print $2}` really
splits every record), both in a `mktemp -d` directory; NR = 21 **interleaved**
runs per gated shape, ND = 300 per-call measurements, timed with
`TStopwatch.getTimeStamp`, stdin closed for the whole run. Measured
**2026-09-24** on Windows 11 / MSYS2 with the machine idle (per-process CPU
sampled), under `bash -eu` (rc 0 on both):

| Measurement | bash 5.2.37 / gawk 5.0.0 | bash 5.3.9 / gawk 5.4.0 |
|---|---|---|
| `buildArgv` — the override (11 words, one extra, one variable) | 2167.6 µs/call | 2164.4 µs/call |
| `argv NAME` (build + validate + copy) | 3228.0 µs/call | 3280.6 µs/call |
| `buildArgv` **refused** (rc 2, `-Wsandbox` after `-n --lint`) | 2398.7 µs/call | 2355.6 µs/call |
| `new PROGRAM` + `sandbox` + `argv` + `delete` — the family's delta row | 5872.9 µs/call | 5732.3 µs/call |
| **`new PROGRAM` + `sandbox` + `buildArgv` + `delete`** — *the `apply` delta* | **4782.2 µs/call** | **4684.1 µs/call** |
| `tawk._enc` on a 1 KiB value (backslashes, newlines, a leading `@`) | 422.0 µs/call | 369.9 µs/call |
| `buildArgv` without / with one 1 KiB `setVar` value | 1300.3 / 1875.8 µs/call | 1311.9 / 1869.6 µs/call |
| the 1 KiB variable's share of a build | ~576 µs | ~558 µs |
| **baseline** — bare `gawk --sandbox -e '{print $2}' -- big.txt`, 10 000 lines (median of 21) | 41.72 ms | 35.85 ms |
| `TAwk.apply '{print $2}' big.txt` (median of 21) | 49.30 ms — **1.18×** | 43.50 ms — **1.21×** |
| **baseline** — bare `gawk --sandbox -e '{print $2}' -- one.txt`, 1 line (median of 21) | 40.51 ms | 35.77 ms |
| `TAwk.apply '{print $2}' one.txt` (median of 21) | 47.46 ms — **1.17×** | 41.66 ms — **1.16×** |
| worst **single** pairing inside those samples (big / one) | 8.71× / 6.20× | 7.11× / 7.68× |
| **baseline** — `gawk --sandbox -e … -- big.txt \| wc -l` (median of 21) | 66.44 ms | 49.11 ms |
| `a.count` — 10 000 records into bash | 323.28 ms — **4.86×** | 313.46 ms — **6.38×** |
| the same sink over **one** record (its fixed half) | 44.74 ms | 39.47 ms |
| per record read into bash | ~27 µs | ~27 µs |
| forks per call | **1** (gawk itself), **0** on a refused call | **1** / **0** |

Reading the table:

- **The gate is the four `TAwk.apply` / baseline rows** ([PLAN.md](PLAN.md) §5
  P1): at most **1.5×** a bare `gawk --sandbox -e … --` on the same file. Both
  shapes pass on both bashes. A second run read **1.15×** / **1.11×** on 5.2.37
  and **1.08×** / **1.19×** on 5.3.9 — the medians move by a few points while
  the means beside them moved by up to 70 ms.
- **The delta is one throw-away instance.** `apply` passes the program to the
  constructor (there is no `addProgram` in it), sets `sandbox = 1`, and `run`
  calls `buildArgv` — the bold row. The constructor assigns **nine** properties
  and declares **four** arrays (tsed: eleven and two); the build walks the whole
  rc 2 list and the extras scan. The family's row (with `argv`, as the tsed and
  tfind benches time it) is ~1.1 ms more, the out-name check and the copy `run`
  never makes. The gate rows' measured delta (6–8 ms) is a little more than the
  bold row, the rest being `run`'s own bookkeeping — the `command -v` probe and
  the `mapRc` dispatch — and the static call. It is a **per-call** cost, never a
  per-record one.
- **The build is heavier than tsed's** (≈2.2 ms against ≈1.1 ms for a
  comparable argv): the §2.2 rc 2 list is longer — the assignment-looking path
  check, the name re-validation of `_vnames`, and a getopt-following scan with a
  long-name table — and the `setVar` words are encoded on every build. A 1 KiB
  value adds ≈0.6 ms, all of it bash parameter expansion; nothing forks.
- **Corpus size is not the knob.** A whole `gawk` run costs ~36–42 ms here (one
  msys process start plus the work); the wrapper's fixed delta is ~5–8 ms. The
  ratio is therefore ~(40 + 6)/40 and can only *fall* as the file grows; the
  one-line row (where the fork *is* the whole measurement) is the pessimistic
  one.
- **Medians, and why they are not negotiable.** Every timed number is one
  process start, and on this box a process start occasionally takes several
  hundred milliseconds for reasons outside this repo: the *means* beside these
  medians ran up to 2× them, and the **worst single pairing** inside these very
  samples read **6.2–8.7×**. A one-shot comparison, or a non-interleaved loop,
  can therefore fail a 1.5× gate on code that is fine — so the two sides are
  timed one-of-each per iteration and the ratio is taken between medians.
  `bench.sh` prints the mean beside every median and the worst single pairing
  under every gate for exactly this reason
  ([`../tfind/PLAN.md`](../tfind/PLAN.md) §8, finding 17).
- **The clock is `TStopwatch.getTimeStamp`, never `date +%s%N`.** On msys the
  latter is its own process at ~20 ms a call — about half of the `gawk` run
  being measured, and paid twice per sample.
- **`argv` runs nothing** and forks nothing: section (a) of the bench points
  `cmd` at a function that counts its own invocations and builds 600 times —
  the counter stays at 0 and `$BASHPID` never changes across 1 200 builds. The
  **rc 2** path is measured too (≈2.4 ms, the whole three-word scan and the `-W`
  table inside it): a refused call does not even pay for the fork.
- **`count` is not the `wc -l` equivalent, and the ~5–6× row is why.** The sink
  reads every record into bash at ~27 µs a record; `wc -l` counts at memory
  speed in one more process. Over 10 000 records the pipeline wins; the sink's
  fixed half (one gawk, ~40–45 ms) is *cheaper* than the pipeline's (~50–66 ms),
  so the crossover is at a few hundred records (≈800 on 5.2.37, ≈360 on 5.3.9,
  by these medians; `tests/007_Bench.sh` sees the two level at 200). That is why the row is **published, not gated** — and why,
  when all you want is the number over a big file, `gawk … | wc -l` is the right
  answer.
- **Zero forks** (section (e)): `$BASHPID` is unchanged across 33 calls — ten
  property writes, every builder member, the five sinks, `run`, `apply`, and
  five rc 2 paths (a `-W` deny-list hit, an in-place sink, a path-less and an
  empty-program `apply`, an illegal `setVar` name) — and inside the `each`
  callback and a `.Add`.
- `tests/007_Bench.sh` asserts the same shapes with a ceiling of **10×**: under
  the threaded runner the two sides do not inflate together (gawk is its own
  process; the wrapper's share is bash work in the contended shell).
