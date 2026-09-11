# tutil — `TUtil`, the CLI-tool wrapper base

> **Status: P0 + P1 landed.** The core (`cmd`/`args`/`argv`, `Create`/`Destroy`,
> `buildArgv`, `addArg`, `clearArgs`, `argv`, `run`, `lastRc`, `mapRc`) **and**
> the five **sinks** (`each`, `toArray`, `toList`, `first`, `count`, each one a
> single [`TPipe`](../tpipe/README.md) call) have real bodies; no stub is left.
> Suite: `tests/001_Core.sh`, `tests/002_Sinks.sh`, `tests/003_Contract.sh` —
> **164 checks green on bash 5.2.37 and on bash 5.3.9**, threaded and under
> `--mode single`. Still to come: `TGrep` (P2) and the bench/doc closeout (P3).
> Design record and phase history: [PLAN.md](PLAN.md) /
> [tutil_ledger.json](tutil_ledger.json).

`TUtil` wraps an external tool the way FPC's `fcl-process` **`TProcess`** does —
`Executable` / `Parameters` / `Execute` / `ExitStatus` become `cmd` /
`${inst}_args` / `run` / `lastRc` — but no class is ported line by line: this is
a kcl design in the spirit of `TProcess`, sized for shell tools instead of for
long-running child processes. It is **concrete**: a generic argv runner is
useful on its own, and a wrapper for a specific tool (`TGrep`, P2) is a
descendant that adds typed properties and overrides `buildArgv`.

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
| `cmd` | var | executable / function / builtin name; `''` = not runnable | — |
| `crlf` | var | `1` → the sinks strip ONE trailing CR per record (`TPipe -c`) | — |
| `nul` | var | `1` → records are NUL-terminated (`TPipe -0`) | — |
| `_lastRc` | var | raw rc of the last `run`/sink; `-1` until one ran | — |
| `buildArgv` | func | **virtual.** Fills `${inst}_argv`. Base: `cmd` + the extras | word count |
| `addArg ARG...` | proc | append to `${inst}_args` — the un-modelled-option hatch | — |
| `clearArgs` | proc | empty `${inst}_args` | — |
| `argv NAME` | func | `buildArgv`, then **copy** into the caller's array. Runs nothing | word count |
| `run` | proc | execute the argv in the foreground, **stdout inherited** | — |
| `lastRc` | func | the raw exit status of the last `run`/sink | that status |
| `mapRc RAW` | func | **virtual.** Normalise a raw status. Base: `0`→0, `127`→1 + one debug line, else 1 silent | the mapped rc |
| `each CB` | proc | `TPipe.each [-0] [-c] CB -- "${argv[@]}"` — `CB RECORD` per record, in **this** shell | — (rc only, §3) |
| `toArray NAME` | func | `TPipe.toArray …` — **replace** the caller's array | records stored |
| `toList INST` | func | `TPipe.toList …` — `INST.Add RECORD` per record | records **offered** |
| `first` | func | `TPipe.first …` — read one record, then stop the producer | the record; `''` **and rc 1** if there was none |
| `count` | func | `TPipe.count …` | records counted |

A `var` is read as `$(u.cmd)` and written as `u.cmd = value` — the kklass
property surface. `argv NAME` follows kcl `README.md` §1.7: the name is
validated *before* any nameref is bound, and the caller's array is **replaced**.

### The three per-instance arrays

`${inst}_args` holds the caller's extras and persists; `${inst}_argv` is the
built command line and is **rebuilt on every `run`, `argv` and sink**;
`${inst}_paths` belongs to `TGrep` (P2). All three are created with
`declare -g -a` and released by the destructor (kcl `README.md` §1.9), so
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
attributed to `kklass.sh`. The answer is rc 1 with `lastRc` = `127`, one
`kk.debug` line naming the member, and **nothing runs** — not even the process
substitution. This is deliberately stricter than `TPipe`, which takes an
arbitrary argv and cannot know the command; `TUtil` owns `cmd`, so it can check
it.

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
`od -c < <(u.run)` came back as `2` + the tool's output + `0`.

### `$( )` loses the instance's state

`$(u.run)` captures the bytes, but the subshell is thrown away with every
mutation it made — the instance's `_lastRc` is **not** updated. Call `run`
directly and read `lastRc` afterwards when you need the status; this is the same
line every kcl instance unit carries.

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

```bash
shopt -s lastpipe                       # once, top of a NON-interactive script
u.run | TPipe.each r.onLine             # 1. a real pipe (needs lastpipe)
declare -a w; u.argv w
TPipe.each r.onLine -- "${w[@]}"        # 2. TPipe's own safe form
u.each r.onLine                         # 3. the sugar — identical to 2
```

All three deliver the same records in the same order; `tests/002_Sinks.sh` §L
runs them side by side in a child script with `shopt -s lastpipe` and compares.

### Flags come from the properties, never from the call

| property | `TPipe` flag | meaning |
|---|---|---|
| `nul = 1` | `-0` | records are NUL-terminated (`find -print0`, `grep -lZ`) |
| `crlf = 1` | `-c` | strip **one** trailing CR per record |

Both default to `0`, and the caller never spells a flag: `u.each -c cb` is not
the surface. The words are built into an array and passed as `"${__tu_fl[@]}"`,
never as an expansion-built option word — `${nul:+-0}` is re-split by the
caller's `IFS`.

`crlf` is a **no-op for GNU grep, sed and awk**, which open input in text mode
and strip the CR themselves on this platform; it exists for `cat`/`head`-style
tools and for bash-function producers, which keep it.

### `each` answers with its rc alone

`each` is a `proc`. `TPipe` does count the records, but `kk._invoke` restores
the **caller's** `RESULT` whenever a body never calls `kk._return`, so reading
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
`each` there is nothing to redirect in the first place.

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

Three rules the base is built around, each of them a bug that was measured
before it was a rule:

* **Do not write `inherited` in a constructor.** The Pascal front-end rewrites
  both `inherited` and `inherited Create` to `parent.constructor "$@"`, which
  forwards the *descendant's* arguments unchanged — `TGrep.Create PATTERN
  PATH...` would hand `TUtil` `cmd=PATTERN` and every path would be emitted
  twice. Call `parent.constructor mytool` explicitly, then assign your own vars.
* **Assign every declared `var` in the constructor.** kklass binds a property as
  a nameref onto `${inst}_data[NAME]`; an unassigned one is an *unbound
  variable* under `set -u`, and `.new` over a still-live instance does not clear
  `_data`, so it can also inherit the previous instance's value.
* **A `func` that answers both a value and a non-zero rc ends with
  `kk._return V; return N`.** An explicit `return` skips the compiled
  `kk._return "$RESULT"` trailer, and `kk._invoke` then restores the *caller's*
  RESULT — a bare `RESULT=V; return N` silently loses `V`.

And one kklass-wide trap that applies to every member body: `build` re-creates
each body from `declare -f` through `eval`, and a literal `$'\r'` written inside
a body does **not** survive that round trip. A control character must come from
a variable built at load time (tpipe `README.md` §7).

### A CR does not survive a compound array assignment either

This one is not kklass's and not this unit's — it is bash on this platform, and
it bites **tests** rather than member bodies. In an array *compound assignment*
a raw CR produced by `$'…'` is dropped, and `declare` strips it even out of a
quoted expansion (measured on 5.2.37 and on 5.3.9; TAB, NL and a backslash are
unaffected, and `shopt igncr` does not exist here):

```bash
x=$'cr\r';   echo "${#x}"        # 3  — a plain assignment is fine
A=( $'cr\r' );  echo "${#A[0]}"  # 2  — the CR is gone
B=( $'a\rb' );  echo "${#B[0]}"  # 2  — "ab"
S=( "cr$CR" )                    # 3  — right: CR from a VARIABLE, quoted
C=( "${S[@]}" );        echo "${#C[0]}"   # 3  — a plain copy keeps it
declare -a D=( "${S[@]}" ); echo "${#D[0]}"   # 2  — `declare` re-parses: gone
```

It is the same "a raw CR does not survive a second parse" class as the `build`
trap above. So an expected-value array that must carry a CR is built as
`printf -v CR '\r'; WANT=( … "cr$CR" … )` and copied with a plain
`COPY=( "${SRC[@]}" )`, never with `declare -a COPY=( … )`. `tests/002_Sinks.sh`
does both and says so in place.

---

## 6. Tests

```bash
bash kcl/tutil/tests/tests.sh                  # 5.2.37
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe kcl/tutil/tests/tests.sh
```

| File | Cases | What it pins |
|---|---|---|
| `001_Core.sh` | 61 | source integrity; the lifecycle (every var present in `${inst}_data` with its default, both arrays created and freed, every var readable under `set -u`); the argv model (`--format=%H` verbatim, `addArg`/`clearArgs`, `argv` is a copy and runs nothing, rebuild without accumulation); `argv`'s out-name validation (11 refusals, each rc 2 with `RESULT=''` and storage intact); `run` (cmd `''` runs nothing and leaves a here-string unread; a missing command is rc 1 + `lastRc` 127 + exactly one stderr line under the switch and none without; a tool exiting 3 is rc 1 + `lastRc` 3 and silent; two instances keep separate `_lastRc`); byte-identity of the stream in all three positions, including a producer emitting `-n`, a backslash, a glob, a CR and an unterminated tail; `mapRc`'s base table; the `set -eu` contract including a failing and a missing tool; and that the P0 sink stubs are **gone** (no member answers `__TUTIL_PENDING__`, the string is absent from the source, all 16 members of the surface are bound) |
| `002_Sinks.sh` | 56 | U1 (`each` delivers, a plain function and an instance member both keep their state, `each` is rc-only); U8 (each `func` sink's RESULT **and** mapped rc, direct, under `$( )` and on the LHS of a pipe, with the value printed exactly once); every sink compared with `TPipe` called directly on the argv `u.argv` handed over, byte-exact over a producer emitting `-n`, `-neE`, a backslash, a glob, a space, UTF-8, a bare CR and an unterminated tail; `nul`→`-0` and `crlf`→`-c` (and off by default); three-frame dispatch `g.each → TPipe.each → r.onLine` and a nested sink inside a callback; zero forks per record (`$BASHPID`); a rejecting `.Add` (THashSet duplicates: 5 offered, 3 kept); the rc 1 + count-kept deviation for all five; `first` answering rc 1 with RESULT '' whenever there was no record, including a producer that SUCCEEDED silently, and staying quiet while doing it; U6 (`TPipe.stop` and `first` on `yes`, in a child under `timeout`, `lastRc` 141/143); every malformed shape (`cmd=''`, a missing command, a non-function CB, an INST without `.Add`, ten refused out-names) with rc, `RESULT`, an untouched `lastRc` and a flag file proving nothing ran; separate `_lastRc` per instance; and the three forms (`u.run \| TPipe.each cb` under `lastpipe` == the `--` form == `u.each cb`) |
| `003_Contract.sh` | 47 | `bash -n` + the open-quote and inline-`$'\r'` greps; every sink from a child script under `set -eu` — a succeeding tool, a tool exiting 3 (the child must die of the member's rc 1, never the tool's 3), a callback answering rc 1 on every record, a `TPipe.stop` where `wait` returns 141/143 while the member answers 0, a rejecting `.Add`, `cmd=''`, a missing command, a malformed CB/out-name/list, and the sinks under `$( )`; the zero-fork probe under `set -eu`; exactly ONE `kk.debug` line on each of the 15 rc 2 / `127` paths and **none** on any rc 0 or plain rc 1 path, with complete silence when the switch is off; and D6's one Warning line for the `--` form under `$( )` |
