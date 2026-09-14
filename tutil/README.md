# tutil — `TUtil`, the CLI-tool wrapper base

> **Status: COMPLETE (P0–P3).** The core (`cmd`/`args`/`argv`,
> `Create`/`Destroy`, `buildArgv`, `addArg`, `clearArgs`, `argv`, `run`,
> `lastRc`, `mapRc`), the five **sinks** (`each`, `toArray`, `toList`, `first`,
> `count`, each one a single [`TPipe`](../tpipe/README.md) call), the bench and
> the docs are all in. Suite: `tests/001_Core.sh`, `tests/002_Sinks.sh`,
> `tests/003_Contract.sh`, `tests/004_Bench.sh` — **172 checks green on bash
> 5.2.37 and 172 on bash 5.3.9**, threaded and under `--mode single`.
> Design record, the TProcess comparison and every measurement the design rests
> on: **[docs/TUtil.md](docs/TUtil.md)**. What the tests pin, case by case:
> **[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md)**. Phase history:
> [PLAN.md](PLAN.md) / [tutil_ledger.json](tutil_ledger.json).
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
source kcl/tutil/tutil.sh

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

— with **no** leaked framework bytes. That is why every internal call inside a
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
source kcl/tgrep/tgrep.sh
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
| `crlf = 1` | `-c` | strip **one** trailing CR per record |

Both default to `0`, and the caller never spells a flag: `u.each -c cb` is not
the surface. The words are built into an array and passed as `"${__tu_fl[@]}"`,
never as an expansion-built option word — `${nul:+-0}` is re-split by the
caller's `IFS`.

### CRLF: which tools keep the CR, and which have already eaten it

Measured on this platform, both bashes, on a `x\r\ny\r\n` file:

| producer | the record for `x\r\n` | `crlf = 1` does |
|---|---|---|
| GNU **grep**, **sed**, **gawk** | `x` — the tool opened the input in **text mode** and stripped the CR itself | nothing; it is a no-op here |
| GNU grep with `binary = 1` (`-U`) | `x\r` — byte fidelity restored | strips it again, which is the byte-faithful pass |
| `cat`, `head`, `tail`, coreutils generally | `x\r` | **strips it** — this is what `crlf` is for |
| a bash **function** producer (`read`/`printf`) | `x\r` | strips it |

So `crlf` is a **no-op for the grep/sed/awk wrappers** and matters for the
coreutils ones (`thead`, `ttail`) and for bash-function producers. A pattern
containing a literal `\r` never matches through a text-mode tool, and `-U` is the
only way back; `binary = 1` **plus** `crlf = 1` is the documented combination for
a byte-faithful pass over a CRLF corpus ([tgrep `README.md` §5](../tgrep/README.md#5-crlf--grep-opens-input-in-text-mode)).

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

---

## 4. Reserved member names

`TUtil` owns

```
cmd  crlf  nul  _lastRc
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
instance's `_data`/`_class`/`_items`), when they start with this family's local
prefixes `__tu_` / `__tg_`, or when they name the instance's own `_args`,
`_argv` or `_paths`.

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

### Every trap this base is built around

Each row was a measured bug before it was a rule (PLAN §6). The repro column is
the shortest thing that shows it.

| # | Rule | What happens if you don't, in one line |
|---|---|---|
| 1 | An internal call to another member is `kk.call_silent "$__inst__" NAME …`, **never `$this.NAME`** | `TStream.run() { $this.pre; printf 'A\n'; }` → `od -c < <(v.run)` shows `2 A \n` — the callee's `kk._return` printed into your stream ([§3.1](docs/TUtil.md#31-c1--thisfunc-prints-under--)) |
| 2 | A `func` that answers a value **and** a non-zero rc ends `kk._return V; return N` | `TR.bare() { RESULT=3; return 1; }` → the caller reads rc 1 and its **own** previous RESULT ([§3.4](docs/TUtil.md#34-c5--resultv-return-n-loses-v)) |
| 3 | Never `inherited` in a **constructor** — call `parent.constructor ARGS` | `TDInherited.Create() { inherited; … }` with `new g needle src/` → `cmd=needle`, and `src/` is in `_args` **and** `_paths` ([§3.2](docs/TUtil.md#32-c2--inherited-in-a-constructor-forwards-)) |
| 4 | Assign **every** declared `var` in the constructor | `TV.Create() { assigned=x; }` then reading `$forgotten` under `set -u` → `kklass.sh: line 375: forgotten: unbound variable` on 5.3.9, silently empty on 5.2.37 ([§3.3](docs/TUtil.md#33-c3--an-unassigned-var-is-unbound-under-set--u--and-the-two-bashes-disagree)) |
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

**172 cases, green on bash 5.2.37 and on bash 5.3.9**, in the default threaded
mode and under `--mode single`. Case-by-case:
[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md).

| File | Cases | What it pins |
|---|---|---|
| `001_Core.sh` | 61 | source integrity; the lifecycle (every var present in `${inst}_data` with its default, both arrays created and freed, every var readable under `set -u`); the argv model (`--format=%H` verbatim, `addArg`/`clearArgs`, `argv` is a copy and runs nothing, rebuild without accumulation); `argv`'s out-name validation (11 refusals, each rc 2 with `RESULT=''` and storage intact); `run` (cmd `''` runs nothing and leaves a here-string unread; a missing command is rc 1 + `lastRc` 127 + exactly one stderr line under the switch and none without; a tool exiting 3 is rc 1 + `lastRc` 3 and silent; two instances keep separate `_lastRc`); byte-identity of the stream in all three positions, including a producer emitting `-n`, a backslash, a glob, a CR and an unterminated tail; `mapRc`'s base table; the `set -eu` contract including a failing and a missing tool; and that the P0 sink stubs are **gone** (no member answers `__TUTIL_PENDING__`, the string is absent from the source, all 16 members of the surface are bound) |
| `002_Sinks.sh` | 56 | U1 (`each` delivers, a plain function and an instance member both keep their state, `each` is rc-only); U8 (each `func` sink's RESULT **and** mapped rc, direct, under `$( )` and on the LHS of a pipe, with the value printed exactly once); every sink compared with `TPipe` called directly on the argv `u.argv` handed over, byte-exact over a producer emitting `-n`, `-neE`, a backslash, a glob, a space, UTF-8, a bare CR and an unterminated tail; `nul`→`-0` and `crlf`→`-c` (and off by default); three-frame dispatch `g.each → TPipe.each → r.onLine` and a nested sink inside a callback; zero forks per record (`$BASHPID`); a rejecting `.Add` (THashSet duplicates: 5 offered, 3 kept); the rc 1 + count-kept deviation for all five; `first` answering rc 1 with RESULT '' whenever there was no record, including a producer that SUCCEEDED silently, and staying quiet while doing it; U6 (`TPipe.stop` and `first` on `yes`, in a child under `timeout`, `lastRc` 141/143); every malformed shape (`cmd=''`, a missing command, a non-function CB, an INST without `.Add`, ten refused out-names) with rc, `RESULT`, an untouched `lastRc` and a flag file proving nothing ran; separate `_lastRc` per instance; and the three forms (`u.run \| TPipe.each cb` under `lastpipe` == the `--` form == `u.each cb`) |
| `003_Contract.sh` | 47 | `bash -n` + the open-quote and inline-`$'\r'` greps; every sink from a child script under `set -eu` — a succeeding tool, a tool exiting 3 (the child must die of the member's rc 1, never the tool's 3), a callback answering rc 1 on every record, a `TPipe.stop` where `wait` returns 141/143 while the member answers 0, a rejecting `.Add`, `cmd=''`, a missing command, a malformed CB/out-name/list, and the sinks under `$( )`; the zero-fork probe under `set -eu`; exactly ONE `kk.debug` line on each of the 15 rc 2 / `127` paths and **none** on any rc 0 or plain rc 1 path, with complete silence when the switch is off; and D6's one Warning line for the `--` form under `$( )` |
| `004_Bench.sh` | 8 | the PLAN §5 P3.1 gates as assertions with a 5× ceiling (`u.each` and `u.toArray` against `TPipe` called directly on the same argv, N = 2000, both shapes warmed first); that 200 `buildArgv` + `argv` calls invoke the `cmd` **zero** times, fork nothing and do not accumulate words; and zero forks for every member — the callback, `.Add` and the `cmd` that `run` executes all report this process's `$BASHPID`, and the only extra pid in a sink call is the one producer |
