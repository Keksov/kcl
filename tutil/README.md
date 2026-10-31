# tutil — `TUtil`, the CLI-tool wrapper base

> **Status: COMPLETE (P0–P3).** The core (`cmd`/`args`/`argv`,
> `Create`/`Destroy`, `buildArgv`, `addArg`, `clearArgs`, `argv`, `run`,
> `lastRc`, `mapRc`), the five **sinks** (`each`, `toArray`, `toList`, `first`,
> `count`, each one a single [`TPipe`](../tpipe/README.md) call), the bench and
> the docs are all in. Suite: `tests/001_Core.sh`, `tests/002_Sinks.sh`,
> `tests/003_Contract.sh`, `tests/004_Bench.sh` — **235 checks green on bash
> 5.3.15 and 5.3.9 (Windows) and on the Linux/FreeBSD lab VMs** (launch L3.4).
> Design record, the TProcess comparison and every measurement the design rests
> on: **[docs/TUtil.md](docs/TUtil.md)**. What the tests pin, case by case:
> **[TEST_COVERAGE_NOTES.md](../docs/dev/tutil/TEST_COVERAGE_NOTES.md)**. Phase history:
> [PLAN.md](../docs/dev/tutil/PLAN.md) / [tutil_ledger.json](../docs/dev/tutil/tutil_ledger.json).
> The first wrapper built on it is [`TGrep`](../tgrep/README.md).

`TUtil` wraps an external tool the way FPC's `fcl-process` **`TProcess`** does —
`Executable` / `Parameters` / `Execute` / `ExitStatus` become `cmd` /
`${inst}_args` / `run` / `lastRc` — but **no class is ported line by line**: this
is a kcl design in the spirit of `TProcess`, sized for shell tools instead of for
long-running child processes. The full member-by-member comparison, including
everything that is wontfix and why, is [docs/TUtil.md §1](docs/TUtil.md#1-tprocess-member-by-member).

It is **concrete**: a generic argv runner is useful on its own, and a wrapper for
a specific tool ([`TGrep`](../tgrep/README.md)) is a descendant that adds typed
properties and overrides `buildArgv`.

```bash
source /path/to/kbool/kbool.sh
kk.uses tutil

TUtil.new u git log --format=%H     # cmd = git, args = (log --format=%H)
u.run                               # runs it; the tool's stdout is inherited
u.lastRc; echo "$RESULT"            # -> 0 — the tool's RAW exit status

u.addArg -n 20                      # append more words
declare -a words
u.argv words                        # RESULT = 5 — the argv is BUILT, not run
                                    # words = (git log --format=%H -n 20)

declare -a shas
u.toArray shas                      # RESULT = ${#shas[@]} — run and collected
u.first;  echo "$RESULT"            # the newest sha; the producer is stopped
u.each  r.onLine                    # one call per record, IN THIS SHELL (§3)
u.delete
```

What that buys over calling the tool by hand:

1. **Typed options → an argv ARRAY, no string building.** No `eval`, no word
   splitting; a path with a space, or a pattern that starts with `-`, is safe by
   construction.
2. **One rc convention.** grep's 0/1/2, sed's 0/1/2/4 and find's 0/1 all collapse
   onto kcl `README.md` §1.2 through `mapRc`, while the raw status stays
   readable through `lastRc`.
3. **The sinks** — `each`, `toArray`, `toList`, `first`, `count` on every
   wrapper, all delegating to [`TPipe`](../tpipe/README.md), so a wrapper is a
   producer that composes with real pipes *and* with the safe `--` form (§3).
4. **A place for the platform notes** (CRLF and text-mode tools, MSYS path
   quirks, GNU-only flags) that otherwise live in every script that calls the
   tool.

---

## 1. Surface

```bash
TUtil.new INST [CMD [ARG...]]    # cmd + the initial extra args
```

| Member | Kind | What it does | RESULT |
|---|---|---|---|
| `cmd` | var | executable / **function** / builtin name; `''` = not runnable | — |
| `crlf` | var | `1` → the sinks strip ONE trailing CR per record (`TPipe -c`) | — |
| `nul` | var | `1` → records are NUL-terminated (`TPipe -0`) | — |
| `_lastRc` | var | raw rc of the last `run`/sink; `-1` until one ran | — |
| `subshellOk` | var | `1` → every sink passes `-s` to `TPipe`, i.e. "the subshell scope is **intended**"; silences TPipe's subshell warning for this instance (§3). Default `0` | — |
| `_textMode` | var | **private.** `1` → the OUTPUT needs the line-end CR strip (§3, the CR contract): where the platform's tool keeps the CR, the sinks add `-c` and `run` filters its stdout. Set by a descendant's `buildArgv` — TGrep with file operands, TAwk only in its `--posix` fallback, TSed never (TSed and TAwk strip on the input side); `0` by default | — |
| `_toolErr` | var | **private.** Why a wrapper's `Create` found no GNU tool: ktool's text, set by `tutil._gnu` (§5); `''` = none, and always `''` for the base. While `cmd` is empty, `buildArgv`'s rc 2 line prints it instead of "cmd is empty" | — |
| `buildArgv` | func | **virtual.** Fills `${inst}_argv`. Base: `cmd` + the extras | word count |
| `addArg ARG...` | proc | append to `${inst}_args` — the un-modelled-option hatch | — |
| `clearArgs` | proc | empty `${inst}_args` | — |
| `argv NAME` | func | `buildArgv`, then **copy** into the caller's array. Runs nothing | word count |
| `run` | proc | execute the argv in the foreground, **stdout inherited** (§2) | — |
| `lastRc` | func | the raw exit status of the last `run`/sink | that status |
| `mapRc RAW` | func | **virtual.** Normalise a raw status. Base: `0`→0, `127`→1 + one debug line, else 1 silent | the mapped rc |
| `each CB` | proc | `TPipe.each [-0] [-c] CB -- "${argv[@]}"` — `CB RECORD` per record, in **this** shell | — (rc only, §3) |
| `toArray NAME` | func | `TPipe.toArray …` — **replace** the caller's array | records stored |
| `toList INST` | func | `TPipe.toList …` — `INST.Add RECORD` per record | records **offered** |
| `first` | func | `TPipe.first …` — read one record, then stop the producer | the record; `''` **and rc 1** if there was none |
| `count` | func | `TPipe.count …` | records counted |

A `var` is read as `$(u.cmd)` and written as `u.cmd = value` — the kklass
property surface. **A plain `var` read at a call site PRINTS its value and leaves
`RESULT` empty**, unlike a `func`, so `$( )` is the only correct read spelling
outside a member body; inside one the var is a nameref (`$cmd`). `argv NAME`
follows kcl `README.md` §1.7: the name is validated *before* any nameref is
bound, and the caller's array is **replaced**.

### The three per-instance arrays

`${inst}_args` holds the caller's extras and persists; `${inst}_argv` is the
built command line and is **rebuilt on every `run`, `argv` and sink**;
`${inst}_paths` belongs to [`TGrep`](../tgrep/README.md). All three are created
with `declare -g -a` and released by the destructor (kcl `README.md` §1.9), so
`u.delete` leaves nothing behind and a new instance that reuses the name starts
empty.

---

## 2. Return contract

| Situation | rc | RESULT | stderr |
|---|---|---|---|
| the tool exited 0 | 0 | — (`run` is a proc) | — |
| the tool exited non-zero | 1 | — | nothing |
| `cmd` is empty (`run`, `argv`, `buildArgv`) | **2** | `''` | one line under the switch |
| `cmd` names nothing `command -v` can find | **1**, `lastRc` = `127` | — | one line under the switch |
| `argv NAME` / `toArray NAME` with a bad output name | **2** | `''` | one line under the switch |
| `buildArgv` / `argv` succeeded | 0 | the word count | — |
| `lastRc` | 0 | the raw status, `-1` if nothing ran | — |
| `mapRc RAW` | 0 | the mapped rc (`0` or `1`) | one line for `127` |
| a sink whose producer succeeded | 0 | the count / the record | — |
| a sink whose producer failed | 1 | **the count is KEPT** (§3) | nothing |
| a sink whose consumer stopped the stream | 0 | the count / the record | nothing |
| `first` with **no** record at all | **1** | `''` | nothing (unless `mapRc` speaks) |
| a sink with a bad `CB` / `INST` / `NAME` | **2** | `''`, `lastRc` **untouched** | one line under the switch |

A diagnostic reaches stderr **only** under `VERBOSE_KKLASS=debug`
(`kk.debug`). rc 2 paths **run nothing**: the tool is not started and stdin is
not touched — a here-string handed to a refused call is still fully readable
afterwards.

**A missing command is pre-checked.** `run` **and every sink** ask
`command -v -- "$cmd"` (a builtin, no fork) before executing, because bash's own
`command not found` line goes to stderr *unconditionally* and would be
attributed to `kklass.sh` ([docs/TUtil.md §3.5](docs/TUtil.md#35-c15--the-command-not-found-line-comes-from-bash-not-from-us)).
The answer is rc 1 with `lastRc` = `127`, one `kk.debug` line naming the member,
and **nothing runs** — not even the process substitution. This is deliberately
stricter than `TPipe`, which takes an arbitrary argv and cannot know the command;
`TUtil` owns `cmd`, so it can check it.

### The one deviation: `run` streams

Every other kcl member returns through `RESULT` and prints nothing
(`README.md` §1.1). `run` is a **stream** member: the tool's stdout is inherited
and passes through byte-for-byte, in every position —

```bash
u.run                       # straight to the terminal
out="$(u.run)"              # captured
od -c < <(u.run)            # a process substitution
u.run | wc -l               # the left-hand side of a pipe
```

— with **no** leaked framework bytes. (The one transformation: where the
platform's tool keeps the line-end CR, a TGrep build with file operands — and
TAwk's `--posix` fallback — sends the stream through a CR filter; the CR
contract, §3.) That is why every internal call inside a
member body is `kk.call_silent "$__inst__" NAME …` and never `$this.NAME`:
`$this.NAME` does not set the silent flag, so the callee's `kk._return` would
*print* whenever the outer member runs under `$( )`, `|` or `<( )`, and
`od -c < <(u.run)` came back as `2` + the tool's output + `0`
([docs/TUtil.md §3.1](docs/TUtil.md#31-c1--thisfunc-prints-under--)).

### `$( )` loses the instance's state

`$(u.run)` captures the bytes, but the subshell is thrown away with every
mutation it made — the instance's `_lastRc` is **not** updated. Call `run`
directly and read `lastRc` afterwards when you need the status; this is the same
line every kcl instance unit carries, and it holds for the sinks too.

---

## 3. The sinks — one `TPipe` call each

A wrapper is a **producer**. The five sinks hand the built argv to
[`TPipe`](../tpipe/README.md)'s `--` form, which reads the records **in the
calling shell** instead of in the subshell a real `|` would create — so a
callback that mutates an object keeps every mutation:

```bash
TUtil.new u git log --format=%H

u.each    r.onLine   #  TPipe.each    [-0] [-c] r.onLine -- git log --format=%H
u.toArray shas       #  TPipe.toArray [-0] [-c] shas     -- …
u.toList  l          #  TPipe.toList  [-0] [-c] l        -- …
u.first              #  TPipe.first   [-0] [-c]          -- …
u.count              #  TPipe.count   [-0] [-c]          -- …
```

Every sink first calls `buildArgv` (**virtual** — a descendant's override is
what runs), then the `command -v` pre-check of §2, then makes exactly one
`TPipe` call. `TPipe` owns the **operand** rules and this unit does not repeat
them: `CB` must be a function, `INST` must have an `.Add`, `NAME` must be a
fillable output array. `toArray` adds one check `TPipe` cannot make — the name
must not be this family's own `__tu_`/`__tg_` scratch or the instance's
`_args`/`_argv`/`_paths`, which would hand the caller the instance's own storage.

### The three forms

All three deliver the same records in the same order. With
[`TGrep`](../tgrep/README.md), which is the wrapper you can run right now:

```bash
source /path/to/kbool/kbool.sh
kk.uses tgrep
shopt -s lastpipe                                   # once, top of a NON-interactive script

TGrep.search needle src/ | TPipe.each r.onLine      # 1. a real pipe (needs lastpipe)

TGrep.new g needle src/; g.recursive = 1
declare -a w; g.argv w
TPipe.each r.onLine -- "${w[@]}"                    # 2. TPipe's own safe `--` form

g.each r.onLine                                     # 3. the sugar — identical to 2
```

Forms 2 and 3 read the records in **this** shell, so a callback that mutates an
object keeps every mutation; form 1 needs `lastpipe`, or the right-hand side runs
in a subshell and the mutations are lost. `tests/002_Sinks.sh` §L and
`tgrep/tests/005_Search.sh` §E run all three side by side in a child script with
`shopt -s lastpipe` and compare the records **and** the callback's final state.

### Flags come from the properties, never from the call

| property | `TPipe` flag | meaning |
|---|---|---|
| `nul = 1` | `-0` | records are NUL-terminated (`find -print0`, `grep -lZ`) |
| `crlf = 1` | `-c` | strip **one** trailing CR per record (also added for the CR contract below) |
| `subshellOk = 1` | `-s` | "the subshell scope is intended" — silences TPipe's subshell warning (below) |

All three default to `0`, and the caller never spells a flag: `u.each -c cb` is not
the surface. The words are built into an array and passed as `"${__tu_fl[@]}"`,
never as an expansion-built option word — `${nul:+-0}` is re-split by the
caller's `IFS`.

### CRLF: one result on every platform

**The contract** (owner decision DL11, 2026-10-21; launch L2.7-C): in **text
mode** — `binary = 0`, and for TSed/TAwk also `inPlace = 0` and
`nullData = 0`, for TGrep also `nullData = 0` — [`TGrep`](../tgrep/README.md),
[`TSed`](../tsed/README.md) and [`TAwk`](../tawk/README.md) deliver every line
**without its line-end CR, on every platform**, and wherever the tool allows it
the script itself **never sees** that CR either: `s/Alice$/Bob/`,
`$2 == "1"`, `/^$/d`, `NF`, `grep -x` on stdin behave as on Windows. A CR the
script or program **writes on purpose** (`s/$/\r/`, `ORS = "\r\n"`,
`printf "x\r\n"`) is kept on every platform. `binary = 1` keeps the bytes,
identically everywhere. One script, one result: a CRLF input (a Windows-made
config or CSV, HTTP text) must not yield `Alice\r` on Linux and `Alice` on
Windows.

Why the wrappers have to act at all: the cygwin/msys builds of grep, sed and
gawk open their input in text mode and drop the CR before the LF themselves —
measured on MSYS2 and Git-bash; the `cygwin*` arm is assumed from those
measurements (no Cygwin host in the lab). The Linux, BSD and macOS builds (GNU
or not, brew included) keep it. `__TUTIL_TOOLS_STRIP_CR` is decided once at
load from `$OSTYPE` (`1` on `cygwin*`/`msys*`, else `0`, no fork); on `1`
nothing is added anywhere — no argv word, no flag, no filter — so the Windows
result and hot path are exactly what they were. On `0` each wrapper uses the
strongest mechanism its tool allows:

| wrapper | text mode on Linux/BSD/macOS | what the tool sees | deliberate CRs |
|---|---|---|---|
| **TSed** | a prelude before the script: `-e 's/<CR>$//' -e 't__tsd_cr' -e ':__tsd_cr'` (raw CR); a `#n` first script line becomes `-n` | no line-end CR on the lines sed reads into the pattern space at cycle start | kept — no output strip |
| **TAwk** | `-v RS='\r?\n'` before the extras and the setVar words | no line-end CR in `$0`, `$NF`, `length`, `NF`; also for `getline` | kept — no output strip |
| **TAwk** + `--posix` / `--traditional` (`-P`, `-c`, any prefix, `-W posix`) | no RS (gawk would split on the CR alone); TUtil's OUTPUT strip instead, one `kk.debug` line | the CR (residual) | a trailing one is removed |
| **TGrep**, no path operand, no `-r` (stdin) | the argv starts with `tutil._crStdin`: stdin goes through `sed [-u] 's/<CR>$//'` first; grep's rc is still grep's | no line-end CR — `$`, `-x`, `^$` as on Windows | grep writes none |
| **TGrep** with file operands | TUtil's OUTPUT strip (`_textMode = 1`): the sinks' `TPipe -c`, `run`'s `sed [-u]` filter | the CR (residual: `needle$`, `-x`, `-Fx`, `^$`) | grep writes none |
| **TGrep** `-l` / `-L` | nothing — the output is names, not lines | — | — |

and on every platform:

| delivery path | `binary = 1` (and TSed/TAwk `inPlace`, `nullData`; TGrep `nullData`) |
|---|---|
| sinks, `run` | the tool's bytes: nothing is stripped, no RS, no prelude, no filter |
| … with `crlf = 1` | exactly one trailing CR stripped per record (`x\r\r` → `x\r`) — the byte-faithful pass that still trims |
| `inPlace = 1` (TSed, TAwk) | derives binary: the file keeps **every** CR on disk |
| `nullData = 1` | TSed/TAwk derive binary, TGrep's `-z` keeps the CR on Windows too: an embedded CR (`x\r\ny`) is kept everywhere |
| sinks with `nul = 1` (a caller's `-0`, TGrep's `-lZ`) | never stripped: a NUL record is not a line |

The output strip and both filters are TUtil's: `_textMode` (private) asks for
the output strip, `tutil._textCr` decides it (`_textMode == 1`, `nul != 1`,
the platform's tool keeps the CR), `tutil._crStdin` is the stdin filter, and
`tutil._sedOpts` gives every filter `sed -u` when this sed takes it (GNU and
FreeBSD do; probed once, on first use), so `tail -f log | g.run` still streams
— the remaining latency is grep's own output buffering into the filter's pipe.
A filter that fails for any reason other than SIGPIPE is not silent: one
`kk.debug` line, and the raw status becomes 2 when the tool itself succeeded.

**Residuals** — platform-specific by design, documented rather than hidden:

* TGrep with **file operands**: grep still reads the CR, so `needle$`, `-x`,
  `-Fx` and `^$` do not match a CRLF line on Linux (they do on Windows, and
  they do on stdin everywhere). Use `binary = 1` and `\r?$`, or feed stdin.
* TSed: a line pulled in **inside** the script (`N`, `n`, `R`) keeps its CR
  off Windows — the prelude runs once per cycle; sed's own error messages
  number the caller's expressions from **#4** (the prelude is #1–#3); the
  label `__tsd_cr` is reserved.
* TAwk: a user `RS` (setVar, an extra `-v RS=`, `BEGIN{RS=…}`, paragraph mode
  `RS = ""`) replaces the CR-optional RS and the program sees the CR again; an
  unterminated last line that ends in a CR keeps it (Windows gawk drops it);
  `RT` is `\r\n` on such lines.
* Windows grep removes **every** CR of a line in a CRLF file (`c\rd\r\n` →
  `cd`); the wrappers elsewhere remove only the line-end one.
* An unterminated last line ending in a CR: Windows sed keeps it (`e\r`), the
  TGrep output strip removes it; `binary = 0` + `crlf = 1` on `x\r\r\n` gives
  `x` on Windows and `x\r` elsewhere.
* Binary mode asked for behind the wrapper's back (`addArg -U`, `setVar
  BINMODE 3`, `BEGIN{BINMODE=3}`) is not seen: the decision reads the
  properties only. `argv` shows the platform's real command line, so it
  differs between Windows and Linux by exactly the words above.

When the matching itself must be byte-identical everywhere, use `binary = 1`
and spell the CR in the pattern or program (`\r?$`, `sub(/\r$/, "")`), then
trim with `crlf = 1`.

**Other producers.** `cat`, `head`, `tail` (coreutils generally) and a bash
**function** producer keep the CR on every platform, and `crlf = 1` is what
strips it there — `thead`/`ttail`/`tfind` and the generic `TUtil` do not take
part in the text-mode contract (`_textMode` stays `0`).

### `each` answers with its rc alone

`each` is a `proc`. `TPipe` does count the records, but `kk._invoke` restores the
**caller's** `RESULT` whenever a body never calls `kk._return`, so reading
`RESULT` after `u.each cb` gives you back whatever was there before. When the
number matters use `count`, or `toArray` and `${#arr[@]}`:

```bash
u.each  r.onLine     # rc only
u.count              # RESULT = how many
```

### The consumer-stop rule

A callback may end the stream with `TPipe.stop`. That is the **consumer's**
success, so `TPipe` answers rc 0 even though the producer was killed and its raw
status is 141 or 143 — and `mapRc` is **not applied** on that path, or the
consumer's success would become rc 1. `lastRc` still shows the raw 141/143.
`first` takes that same path for free on every record it reads, which is why
`u.first` on an endless producer answers in milliseconds:

```bash
TUtil.new y yes
y.first 2>/dev/null   # RESULT = 'y', rc 0
y.lastRc              # RESULT = 141 (or 143 — which signal wins is a race)
```

### The named deviation: rc 1 with a real `RESULT`

For `each`, `toArray`, `toList` and `count`, rc 1 means *the producer exited
non-zero*, not *no answer*: **`RESULT` still carries the count**, `toArray`'s
array and `toList`'s list still hold everything that arrived, and everything the
callback did still happened. This is `TPipe`'s named deviation from kcl
`README.md` §1.2 (tpipe `README.md` §4) and it matters for grep, which answers 2
*while still delivering matches* when one file of many is unreadable. Callers who
want all-or-nothing test the rc first.

`first` is the odd one out, and it does **not** deviate: its `RESULT` is the
record, rc 0 means a record was read, and **rc 1 means there was none** —
whatever the producer's status turned out to be. A `grep` that matched nothing
(raw 1) and a tool that succeeded silently (raw 0) are the same question
answered the same way:

```bash
TUtil.new e true
e.first          # rc 1, RESULT=''  — no record
e.lastRc         # RESULT = 0       — the tool was perfectly happy
e.count          # rc 0, RESULT=0   — ask this one when you want "how many"
```

`mapRc` still *runs* on that path so that a descendant's diagnostic for a real
tool error (TGrep: raw ≥ 2) is emitted, but its value is discarded.

### What a sink prints

**A sink adds no bytes of its own to the stream.** `toArray`, `toList`, `first`
and `count` are ordinary `func`s — a direct call prints nothing and answers in
`RESULT`, `$( )` prints that value exactly **once** — and `each`, having no
return channel, prints exactly what its callback printed and nothing else:

```bash
n="$(u.count)"              # 2          — not '22'
u.each cb | wc -l           # the callback's lines, no record count
out="$(u.toList l)"         # whatever a printing `.Add` wrote, then the count
```

That works because every sink declares **`local __TPIPE_QUIET=1`** before
delegating. `tpipe._ret` prints `RESULT` under any `BASH_SUBSHELL > 0`, which is
right for a caller that *is* the answer and wrong for one that *composes*: the
sink's own `kk._return` would print the same value a second time
(`$(u.count)` measured as `22`). `kk.call_silent` cannot help — `tpipe._ret`
does not read `__kk_return_silent`, and kklass's thin static dispatcher sets
that flag for every static body anyway — so `TPipe` carries a dedicated,
dynamically scoped opt-out (tpipe `README.md` §7) that the composing caller
declares in its own frame. A redirect would not have done: `>/dev/null` on the
delegated call also swallows a callback's and a `.Add`'s own output, and for
`each` there is nothing to redirect in the first place. The whole measurement is
[docs/TUtil.md §3.6](docs/TUtil.md#36-p1-f1--__tpipe_quiet-and-why-a-redirect-is-not-the-fix).

One consequence of dynamic scoping: a **callback** invoked by a sink also sees
the `1`, so a callback that itself captures a sink (`x=$(TPipe.count -- …)`)
must declare `local __TPIPE_QUIET=0` first.

Under `$( )` the instance's `_lastRc` is **not** updated either — the subshell is
thrown away with the mutation, the same line §2 carries for `run`.

### `subshellOk` — the subshell warning, and how to say you meant it

A sink always delegates in `TPipe`'s `--` form, so when the sink itself runs in a
subshell `TPipe` warns exactly as it does on a direct call
([tpipe README §3](../tpipe/README.md#3-a-sink-in-a-subshell--d6-final), owner
ruling **D6 final**, 2026-09-15). One line on stderr, printed **with the debug
switch off**, changing neither the rc nor `RESULT`:

```bash
n="$(u.toArray results)"    # -> n=4, and one line on stderr:
# Warning: TPipe.toArray: the array results is filled inside a subshell (BASH_SUBSHELL=1) — the calling shell will not see it; move the call out of $( ) / ( ); if the subshell scope is intended, pass -s or set KK_SUBSHELL_OK=1
```

The member named in the line is the **`TPipe`** member the sink delegated to, not
the `TUtil` one — that is where the flag and the variable live. Which calls warn
is `TPipe`'s rule, unchanged by the wrapper: `toArray`, `toList` and
`each` **with an instance-member callback** do; `each` with a plain function,
`count` and `first` never do (`n="$(u.count)"` is the intended spelling and is
silent by design).

Three ways to silence it, all of which leave everything else alone:

```bash
u.subshellOk = 1                 # this instance, until it is set back to 0
KK_SUBSHELL_OK=1 u.toArray a     # one call — reaches TPipe through this frame
VERBOSE_KKLASS=quiet             # every warning of every kcl unit
```

`subshellOk` is the object-style spelling of `TPipe`'s `-s` flag and **nothing
else**: `tutil._prep` appends `-s` to the flag array when it is `1`, next to
`nul`→`-0` and `crlf`→`-c`. The dynamically scoped `KK_SUBSHELL_OK` needs no
`TUtil` code at all — it is visible in this frame and in `TPipe`'s below it, so
it works through any depth of wrapper, `TGrep` included. Both are read **per
call**, so setting the property back to `0` re-arms the warning immediately.

---

## 4. Reserved member names

`TUtil` owns

```
cmd  crlf  nul  _lastRc  subshellOk  _textMode  _toolErr
buildArgv  addArg  clearArgs  argv  run
each  toArray  toList  first  count  lastRc  mapRc
```

and kklass owns `property call parent delete` on every instance. A **descendant
must not declare a `var` with any of those names**: the method wrapper is
generated after the property wrapper and wins silently, so `obj.count = 5` would
be accepted and quietly discarded. The planned wrappers (`thead`, `ttail`) use
`lines`/`bytes` for exactly this reason.

Output-array names are refused (rc 2, nothing written) when they are not plain
identifiers, when they are in kklass's reserved set (`this`, `__inst__`,
`__class__`, `RESULT`, `REPLY`, `IFS`, `state`, the `__kk_`/`__KK_` space, the
instance's `_data`/`_class`/`_items`), and through **two registries** every
descendant extends at load (§5):

* **`TUTIL_OUT_PREFIXES`** — the family's local prefixes: `__tu_ __tg_ __th_
  __tt_` at load, plus `__tfd_` once tfind is sourced and `__tsd_` once tsed is;
  a name that starts with any of them is refused;
* **`TUTIL_OUT_SUFFIXES`** — the per-instance arrays beyond kklass's three:
  `_args _argv _paths` at load, plus `_exprs _rfrom _rto _rflags` once tsed is
  sourced; `${inst}${suffix}` is refused for the receiving instance.

Two guards apply to both: each registry's own **name** is refused as an
out-name, and an empty, unset or non-indexed-array registry **fails closed** —
it refuses every name.

---

## 5. Writing a descendant

```bash
class TMyTool : TUtil
    public
        var someOption
        constructor Create
        override func buildArgv
        override func mapRc
end
```

A descendant gets `run` and all five sinks **for free**: they call `buildArgv`
and `mapRc` through `kk.call_silent`, which dispatches **virtually**, so the
override is what runs and what decides the rc. There is nothing to re-implement.
[`TGrep`](../tgrep/README.md) is the worked example, and
[docs/TUtil.md §4](docs/TUtil.md#4-the-template-for-the-next-wrappers) is the
template for the next five wrappers.

**A GNU wrapper calls `tutil._gnu FAMILY` right after `parent.constructor`**
(launch L3.4). FAMILY is a family of the kkore unit `ktool`, the GNU tool
resolver (kkore README §7): `sed awk grep find head tail` (TAwk's is `awk`). `tutil.sh` loads ktool (`kk.uses ktool`), so the wrapper keeps
`kk.uses tutil` as its only dependency:

```bash
TMyTool.Create() {
    parent.constructor sed          # spelled out, never `inherited` (trap 3)
    tutil._gnu sed                  # cmd = ktool's GNU sed (absolute path)
    someOption=''                   # ... then every declared var (trap 4)
}

TMyTool.buildArgv() {
    local -n __tm_v="${__inst__}_argv"
    __tm_v=()
    if [[ -z "$cmd" ]]; then
        kk.debug "Error: TMyTool.buildArgv: ${_toolErr:-cmd is empty; there is nothing to run}"
        kk._return ""
        return 2
    fi
    ...
```

* `tutil._gnu` (rc 0 always; it prints nothing) sets `cmd` to the absolute path
  `ktool.gnu FAMILY` answers (the override `KCL_GNU_<FAMILY>` first, then the
  g-name, then the plain name on PATH) and `_toolErr` to `''`. With no GNU build it sets `cmd` to `''` and
  `_toolErr` to ktool's reason — `no GNU sed: gsed not on PATH; /usr/bin/sed is
  not GNU sed (--version: "sed: illegal option -- -"); FreeBSD: pkg install
  gsed` — and **creation still succeeds** (rc 0, silent): the instance is
  disarmed, and the first `run`, sink or `argv` (and so every static that
  builds one) answers **rc 2** with that text as its one `kk.debug` line,
  `lastRc` untouched (still `-1`), nothing run.
* The `cmd`-empty branch of the descendant's `buildArgv` prints
  `${_toolErr:-cmd is empty; there is nothing to run}` — the base's own branch
  does the same.
* The answer is **frozen** in `cmd`: a later `PATH` or `KCL_GNU_<FAMILY>` change
  reaches the next `.new`, not this instance. A `cmd` the caller sets afterwards
  is used **verbatim** (no identity check) and re-arms a disarmed instance;
  `_toolErr` keeps its text but is not printed while `cmd` is non-empty. The
  validated way to pick a build is `KCL_GNU_<FAMILY>` before `.new`.
* `.new` inside `$( )` resolves in the child, and the cache dies with it: call
  `ktool.gnu FAMILY` (or create one instance) once in the main shell first.
* The generic runner never calls it: `TUtil.new u git …` keeps the `cmd` the
  caller gave. TUtil's own CR filter (§3) stays on plain `command sed`, written
  for BSD and busybox sed too — routing it through ktool would make TGrep and
  TAwk's `--posix` fallback need GNU sed besides their own tool.

**A new wrapper appends its own local prefix to the `TUTIL_OUT_PREFIXES`
registry.** The helper that refuses an output-array name passes this family's
prefixes to `kk._outName`, and the list is shared by every descendant because
the sinks are inherited. `tutil.sh` declares it ONCE per process (kcl/README.md
§1.10 rule 7: a `kk.unit --forget tutil` + reload keeps the descendants'
entries) and `tutil._badOut` reads it:

```bash
if [[ -z ${TUTIL_OUT_PREFIXES+x} || ${TUTIL_OUT_PREFIXES@a} != *a* ]]; then   # tutil.sh, at load
    declare -ga TUTIL_OUT_PREFIXES=( __tu_ __tg_ __th_ __tt_ )
fi
...
if ! kk._outName "$__tu_n" "${TUTIL_OUT_PREFIXES[@]}"; then  # tutil._badOut
```

A descendant appends its prefix at load, **only if absent**, so a second load
(after a `--forget`) adds nothing (`tfind.sh` is the worked example):

```bash
TUTIL_OUT_PREFIXES+=( __tfd_ )
```

Bash scopes locals **dynamically**, so a caller array named like the scratch
nameref a member body holds (`__tg_p`, `__th_v`, …) would be bound to the
instance's own storage and the caller's array would stay empty while `RESULT`
reported a healthy count. Pick a prefix of the shape `__t<two letters>_` (or
three, as `__tfd_` / `__tsd_`), use it for every local in the unit, and append it
to the registry in the same commit; the family's prefixes are pinned in
`tests/001_Core.sh` §C.

**A new wrapper that keeps its own per-instance array appends that array's
suffix to the second registry, `TUTIL_OUT_SUFFIXES`.** Next to kklass's
`_data`/`_class`/`_items`, this family keeps `${inst}_args` and `${inst}_argv`
(TUtil), `${inst}_paths` (every path-taking descendant) and `${inst}_exprs`,
`${inst}_rfrom`, `${inst}_rto`, `${inst}_rflags` (tsed; the last three hold the
raw `addReplace` data). Filling one of those as an output array hands the
caller the instance's own storage — measured on tsed, `s.toArray s_exprs`
turned the records into the NEXT run's script. `tutil.sh` declares the list at
load and `tutil._badOut` refuses `${inst}${suffix}` for every entry:

```bash
declare -ga TUTIL_OUT_SUFFIXES=( _args _argv _paths )        # tutil.sh, at load
TUTIL_OUT_SUFFIXES+=( _exprs )                               # tsed.sh, each only if absent,
TUTIL_OUT_SUFFIXES+=( _rfrom _rto _rflags )                  #   in one loop
```

Two guards live in `tutil._badOut`, apply to **both** registries, and are not
negotiable (tfind PLAN §2.6, the critic's blocker 1; tsed PLAN §2.1):

* **each registry's own name — `TUTIL_OUT_PREFIXES`, `TUTIL_OUT_SUFFIXES` — is
  refused as an out-name** — without that one `u.argv TUTIL_OUT_PREFIXES`
  replaces the registry with the argv and every `__tu_`/`__tg_`/… name becomes
  fillable process-wide;
* **it fails closed** — bash ≥ 4.4 does not even fault `"${arr[@]}"` on an unset
  array under `set -u`, so a registry that is empty, unset or not an indexed
  array refuses **every** name rather than none.

### Every trap this base is built around

Each row was a measured bug before it was a rule (PLAN §6). The repro column is
the shortest thing that shows it.

| # | Rule | What happens if you don't, in one line |
|---|---|---|
| 1 | An internal call to another member is `kk.call_silent "$__inst__" NAME …`, **never `$this.NAME`** | `TStream.run() { $this.pre; printf 'A\n'; }` → `od -c < <(v.run)` shows `2 A \n` — the callee's `kk._return` printed into your stream ([§3.1](docs/TUtil.md#31-c1--thisfunc-prints-under--)) |
| 2 | A `func` that answers a value **and** a non-zero rc ends `kk._return V; return N` | `TR.bare() { RESULT=3; return 1; }` → the caller reads rc 1 and its **own** previous RESULT ([§3.4](docs/TUtil.md#34-c5--resultv-return-n-loses-v)) |
| 3 | Never `inherited` in a **constructor** — call `parent.constructor ARGS` | `TDInherited.Create() { inherited; … }` with `new g needle src/` → `cmd=needle`, and `src/` is in `_args` **and** `_paths` ([§3.2](docs/TUtil.md#32-c2--inherited-in-a-constructor-forwards-)) |
| 4 | Assign **every** declared `var` in the constructor | `TV.Create() { assigned=x; }` then reading `$forgotten` under `set -u` → `kklass.sh: line 375: forgotten: unbound variable` on 5.3.9, silently empty on 5.2.37 ([§3.3](docs/TUtil.md#33-c3--an-unassigned-var-is-unbound-under-set--u-and-the-two-bashes-disagree)) |
| 5 | A descendant never declares a `var` named like an ancestor member | `var count` in a descendant → `obj.count = 5` is accepted and discarded; the method wrapper is generated after the property wrapper and wins |
| 6 | In `run`, `"${argv[@]}" \|\| rc=$?`, never bare | a bare `"${argv[@]}"` with a tool that exits 3 → a `set -e` caller dies **before** `_lastRc` is stored, so `lastRc` still reads `-1` |
| 7 | `buildArgv` never leaves the argv empty — `cmd` is element 0 or it is rc 2 | `"${argv[@]}"` on an empty array is harmless on both targets, but running "nothing" successfully is worse than refusing |
| 8 | A boolean property is `[[ "$x" == 1 ]]`, never `(( x ))` | `g.ignoreCase = yes; (( ignoreCase ))` → `0` in silence; `g.ignoreCase = 'a[0]'` → an arithmetic **injection** |
| 9 | An integer option goes through `kk.isInt` first and is read back from `$__KK_INT`, with `>= 0` checked separately | `kk.isInt -1` succeeds and `grep -m -1` means *no limit*, silently; the OUTVAR form of `kk.isInt` writes **through the property nameref** and would rewrite the caller's `08` on the instance |
| 10 | `kk.call_silent … buildArgv` is the **virtual** call; `inherited buildArgv` is the static one | a descendant that calls `inherited buildArgv` gets the base's `cmd + args` line, not its own |
| 11 | Rebuild an array through a nameref (`local -n a="${__inst__}_argv"; a=()`) | `unset "${inst}_argv[…]"` in double quotes is the G2-01 trap: the subscript is expanded by `unset`, not by the shell |
| 12 | No `$'…'` holding a control character inside a member body | `build` re-creates every body from `declare -f` through `eval`, and a literal CR does not survive the round trip — build it at load time and reference the variable (tpipe `README.md` §7) |
| 13 | Every sink declares `local __TPIPE_QUIET=1` | without it `$(u.count)` reads `22`, and `u.each cb \| cat` carries the record count ([§3.6](docs/TUtil.md#36-p1-f1--__tpipe_quiet-and-why-a-redirect-is-not-the-fix)) |
| 14 | `first` answers rc 1 whenever `TPipe.first` answered non-zero | "there was no record" is `first`'s own answer; mapping the producer's rc there would make a silent success look like a failure |
| 15 | A plain `var` read at a **call site** prints and leaves `RESULT` empty | `u.crlf; use "$RESULT"` reads whatever was in `RESULT` before; the spelling is `$(u.crlf)` |
| 16 | Under `$( )` a sink's `_lastRc` update is lost with the subshell | `n="$(u.count)"; u.lastRc` → the status of the call **before** that one |
| 17 | A tool with **no path operand** reads stdin — including, in TPipe's `--` form, the calling shell's | document it, do not "fix" it; `TGrep.search` is the one member that refuses the zero-path shape |

### And two that bite **tests**, not member bodies

| # | Rule | Repro |
|---|---|---|
| 18 | A CR does not survive a **word of an array compound assignment**, and `declare` re-parses and drops it again | `A=( $'cr\r' ); echo "${#A[0]}"` → `2`. Build it as `printf -v CR '\r'; A=( "cr$CR" )` → `3`, and copy with a plain `C=( "${A[@]}" )`, never `declare -a C=( … )` ([§3.7](docs/TUtil.md#37-p1-f2--a-cr-does-not-survive-an-array-compound-assignment)) |
| 19 | A test file installs **no** `trap … EXIT` of its own, and makes symlinks through the tdirectory helper | its own trap replaces ktests', which prints the `__COUNTS__` line the runner parses; a plain `ln -s` produces a **directory copy** on this box, which `-r` then descends for the wrong reason |

---

## 6. Performance

`bash kcl/tutil/bench.sh [N] [ND]` — deterministic sizes, no `$RANDOM`, timed
with `TStopwatch.getTimeStamp` (the shared fork-free µs clock), N = 10 000
records and ND = 300 calls by default. Measured **2026-09-11** on Windows 11 /
MSYS2 with the threaded test runner idle:

| Measurement | bash 5.2.37 | bash 5.3.9 |
|---|---|---|
| `buildArgv` (base: `cmd` + the extras) | 266.8 µs/call | 295.9 µs/call |
| `argv NAME` (build + validate + copy) | 779.2 µs/call | 793.0 µs/call |
| bare `true` | 2.3 µs/call | 3.9 µs/call |
| `command true` | 2.9 µs/call | 3.0 µs/call |
| `u.run` on `true` | 1026.4 µs/call | 1123.4 µs/call |
| **baseline** — `TPipe.each` + a no-op fn, DIRECT on the same argv, 10 000 records | 2078 ms (207.8 µs/rec) | 2072 ms (207.2 µs/rec) |
| `u.each` + the same no-op fn | 2030 ms (203.0 µs/rec) — **0.97×** | 2089 ms (208.9 µs/rec) — **1.00×** |
| **baseline** — `TPipe.toArray`, DIRECT on the same argv | 1782 ms (178.2 µs/rec) | 1874 ms (187.4 µs/rec) |
| `u.toArray` | 1873 ms (187.3 µs/rec) — **1.05×** | 1798 ms (179.8 µs/rec) — **0.95×** |
| `u.each` + an **instance member** (`r.onLine`) | 4428 ms (442.8 µs/rec) — **2.18×** | 4290 ms (429.0 µs/rec) — **2.05×** |
| forks **per record** | **0** | **0** |

Reading the table:

- **The gate is the `u.each` row** (PLAN §5 P3.1): a sink must cost at most
  **1.1×** `TPipe` called directly on the very same argv, because the delegation
  is one prologue per **call** and zero work per record. It passes on both bashes
  with the ratio sitting on 1.00 — the ±5% either side is measurement noise, and
  the numbers cross over between the two bashes, which is what noise looks like.
- **The wrapper's cost is per CALL, not per record.** `u.run` on `true` is about
  **1 ms**: two kklass instance dispatches (`buildArgv`, `mapRc`) plus one
  `command -v`. Against a stream of 10 000 records at 200 µs each that is 0.05%
  of the total; against a loop that starts `true` three hundred times it is
  everything. Build the instance once and stream, don't call `run` in a loop.
- **`argv` and `buildArgv` run nothing at all** and fork nothing: `bench.sh`
  section (a) points `cmd` at a function that counts its own invocations and
  builds 600 times — the counter stays at 0 and `$BASHPID` never changes.
- **Per call**: one fork — the producer — plus the process-substitution plumbing.
  **Per record: zero forks**, pinned with `$BASHPID` probes in
  `tests/002_Sinks.sh` §F and `tests/004_Bench.sh` §C, which also assert that the
  `cmd` a `run` executes reports **this** process's pid.
- **An instance-member callback is a different order of magnitude, and it is
  kklass's price, not this unit's and not TPipe's** (tpipe `bench.sh` section (a)
  measures the dispatch on its own: ~166 µs against ~8 µs for a plain function).
  Callers with 10⁵-record streams reach for `toArray` + a plain loop, or for a
  plain-function callback that forwards to the object only when it must:

  ```bash
  onLine() { [[ "$1" == *ERROR* ]] && r.onError "$1"; return 0; }
  u.each onLine                       # one dispatch per HIT, not per record
  ```

- **Small N.** The 1.1× gate is calibrated for N = 10 000. At `bench.sh 200` the
  fixed per-call millisecond is a visible fraction of a 26 ms measurement and the
  ratio reads ~1.13× — that is not a regression, re-run at the default N.
- `tests/004_Bench.sh` asserts the same two shapes with a ceiling of **5×**,
  because ktests runs test files threaded with 8 workers by default; under that
  load the same two cases have been seen at 0.94× and 1.87×.

---

## 7. Tests

```bash
bash kcl/tutil/tests/tests.sh                  # 5.2.37
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe kcl/tutil/tests/tests.sh
```

**235 cases, green on bash 5.2.37 and on bash 5.3.9** (launch L2.7-C; +9 in launch L3.4), in the default threaded
mode and under `--mode single`. Case-by-case:
[TEST_COVERAGE_NOTES.md](../docs/dev/tutil/TEST_COVERAGE_NOTES.md).

| File | Cases | What it pins |
|---|---|---|
| `001_Core.sh` | 95 | source integrity; the lifecycle (every var present in `${inst}_data` with its default, both arrays created and freed, every var readable under `set -u`); the argv model (`--format=%H` verbatim, `addArg`/`clearArgs`, `argv` is a copy and runs nothing, rebuild without accumulation); `argv`'s out-name validation (11 refusals, each rc 2 with `RESULT=''` and storage intact); `run` (cmd `''` runs nothing and leaves a here-string unread; a missing command is rc 1 + `lastRc` 127 + exactly one stderr line under the switch and none without; a tool exiting 3 is rc 1 + `lastRc` 3 and silent; two instances keep separate `_lastRc`); byte-identity of the stream in all three positions, including a producer emitting `-n`, a backslash, a glob, a CR and an unterminated tail; `mapRc`'s base table; the `set -eu` contract including a failing and a missing tool; and that the P0 sink stubs are **gone** (no member answers `__TUTIL_PENDING__`, the string is absent from the source, all 19 members of the surface are bound, `subshellOk` among them with its `0` default, `_textMode` since L2.7-C and `_toolErr` since L3.4); and `tutil._gnu` (launch L3.4) through a descendant defined in the test file — a stub via `KCL_GNU_SED` (`cmd` = the stub path, `_toolErr` `''`), a second stub leaving a live instance alone while `.new` over its name re-resolves (frozen), `KCL_GNU_SED=/nonexistent` (`.new` rc 0 and silent, `cmd` `''`, `argv`, `run` and a sink (`count`) rc 2 with exactly one line = ktool's text, `lastRc` still `-1`, nothing run), re-armed by `cmd = …`, an unknown family (ktool's rc 2 text), and the generic `TUtil.new u printf …` never resolving |
| `002_Sinks.sh` | 64 | U1 (`each` delivers, a plain function and an instance member both keep their state, `each` is rc-only); U8 (each `func` sink's RESULT **and** mapped rc, direct, under `$( )` and on the LHS of a pipe, with the value printed exactly once); every sink compared with `TPipe` called directly on the argv `u.argv` handed over, byte-exact over a producer emitting `-n`, `-neE`, a backslash, a glob, a space, UTF-8, a bare CR and an unterminated tail; `nul`→`-0` and `crlf`→`-c` (and off by default); three-frame dispatch `g.each → TPipe.each → r.onLine` and a nested sink inside a callback; zero forks per record (`$BASHPID`); a rejecting `.Add` (THashSet duplicates: 5 offered, 3 kept); the rc 1 + count-kept deviation for all five; `first` answering rc 1 with RESULT '' whenever there was no record, including a producer that SUCCEEDED silently, and staying quiet while doing it; U6 (`TPipe.stop` and `first` on `yes`, in a child under `timeout`, `lastRc` 141/143); every malformed shape (`cmd=''`, a missing command, a non-function CB, an INST without `.Add`, ten refused out-names) with rc, `RESULT`, an untouched `lastRc` and a flag file proving nothing ran; separate `_lastRc` per instance; and the three forms (`u.run \| TPipe.each cb` under `lastpipe` == the `--` form == `u.each cb`); and the **D6-final** matrix as it reaches a caller through a wrapper — `$(u.toArray NAME)` and `$(u.toList INST)` each warn ONCE with the `TPipe` line verbatim, `subshellOk = 1` silences every sink of that instance and is read per call (setting it back re-arms), `KK_SUBSHELL_OK=1 u.toArray …` silences through two wrapper frames, `VERBOSE_KKLASS=quiet` silences it, `$(u.count)` / `$(u.first)` never warn, and `$(u.each r.onLine)` warns while `$(u.each fn)` does not |
| `003_Contract.sh` | 51 | `bash -n` + the open-quote and inline-`$'\r'` greps; every sink from a child script under `set -eu` — a succeeding tool, a tool exiting 3 (the child must die of the member's rc 1, never the tool's 3), a callback answering rc 1 on every record, a `TPipe.stop` where `wait` returns 141/143 while the member answers 0, a rejecting `.Add`, `cmd=''`, a missing command, a malformed CB/out-name/list, and the sinks under `$( )`; the zero-fork probe under `set -eu`; exactly ONE `kk.debug` line on each of the 15 rc 2 / `127` paths and **none** on any rc 0 or plain rc 1 path, with complete silence when the switch is off; and the **D6-final** rules at contract level — `$(u.count)`/`$(u.first)` never warn (switch on or off), `$(u.toArray NAME)` warns ONCE with the debug switch **off** and the same single line under `debug`, `subshellOk = 1` / `KK_SUBSHELL_OK=1` / `VERBOSE_KKLASS=quiet` each silence it with `RESULT` unchanged, and a DIRECT sink call warns about nothing |
| `004_Bench.sh` | 8 | the PLAN §5 P3.1 gates as assertions with a 5× ceiling (`u.each` and `u.toArray` against `TPipe` called directly on the same argv, N = 2000, both shapes warmed first); that 200 `buildArgv` + `argv` calls invoke the `cmd` **zero** times, fork nothing and do not accumulate words; and zero forks for every member — the callback, `.Add` and the `cmd` that `run` executes all report this process's `$BASHPID`, and the only extra pid in a sink call is the one producer |
| `005_TextMode.sh` | 17 | the CR contract at the base (§3, owner DL11), both platform paths driven on any host by flipping `__TUTIL_TOOLS_STRIP_CR` and using a CR-writing function as the tool: `_textMode` is a var with default `0` and the global is `1` exactly on cygwin/msys; with `_textMode = 0` every CR survives every sink and `run` on both paths; the output-strip path drops ONE trailing CR per record in all five sinks (a CR inside a record and the second of two stay, an unterminated `c\r` becomes `c`), `run` streams LF-only lines, keeps a CR inside a line and an unterminated tail unterminated, still hands the caller's stdin to the tool, and reports the TOOL's raw rc (3 → rc 1, `lastRc` 3); the native path adds nothing (the tool's own CRs reach every sink, `run` is byte-identical and executes the tool in this shell); `nul = 1` is never stripped, by the sinks or by `run`; `crlf = 1` + text mode strips one CR, not two; `run` on the strip path under `set -euo pipefail` in a child; a FAILING filter (a fake `sed` exiting 4: `lastRc` 2, rc 1, one debug line; a tool rc 3 wins; `tutil._crStdin` answers 2); `tutil._crStdin` (LF lines reach the tool, its rc comes back, SIGPIPE is not an error); and `sed -u` exactly when this sed accepts it, probed once |

**`tests/gnu_helper.sh`** (launch L3.4) is the shared
GNU-tool helper of the wrapper family — a sourced library, not a test file (the
runner collects `NNN_*.sh` only; precedent `kcl/tdirectory/tests/symlink_helper.sh`).
A wrapper's test file sources it after its unit
(`source "$UNIT_DIR/../tutil/tests/gnu_helper.sh" || exit 1`):

* `kt_gnu_gate FAMILY VAR` — ONE case, "GNU FAMILY: ktool resolves it", run in
  the test's main shell (the ktool cache is then warm for every `.new` in the
  file). Found: `VAR` = the path, `GNU_OK=1`, `GNU_WHY=''`, the case passes
  `PATH — BANNER`. None: `VAR=''`, `GNU_OK=0`, `GNU_WHY` = `ktool.lastError`'s
  text, the case passes `SKIP: GNU_WHY` — and the file's `tcase` passes every
  later case as `SKIP: $GNU_WHY`, so the count is the same either way. rc 2
  from ktool (a FAMILY typo, or ktool not loaded): the gate case **FAILS** —
  never a silent SKIP of a whole file — with `GNU_OK=0` and `GNU_WHY` set.
* `kt_gnu_stub FAMILY DIR VAR` — writes `DIR/FAMILY`, a `#!/bin/sh` script that
  answers `--version` with a GNU banner (`sed (GNU sed) 4.9`, `GNU Awk 5.3.0`,
  `grep (GNU grep) 3.11`, `find (GNU findutils) 4.10.0`, `head (GNU coreutils)
  9.4`, `tail (GNU coreutils) 9.4`) and anything else with `.:DIR/share/awk`
  (TAwk's AWKPATH probe), creates an empty `DIR/share/awk/inplace.awk`, sets the
  shell variable `KCL_GNU_<FAMILY>` and `VAR` to `DIR/FAMILY`.
  A `.new` after it resolves the stub, so an argv-pin file (004) runs its full
  count on every box and pins the same word 0 everywhere; the real tool never
  runs. `KCL_GNU_<FAMILY>` is **not exported**: `$( )` sees the stub, but a
  child PROCESS (`bash -c`, `timeout bash child.sh`, a contract test that runs
  a child script) resolves the REAL tool. `DIR` must be absolute — start with
  `/` and hold no `:` (a relative DIR makes `VAR` differ from the
  `$PWD`-absolute path ktool answers; a `C:/…` DIR breaks the `.:DIR/share/awk`
  answer, whose separator is `:`). rc 1 (nothing written) for an unknown
  FAMILY, an empty `VAR` or a `DIR` that breaks that rule.
