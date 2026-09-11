# tutil — `TUtil`, the CLI-tool wrapper base

> **Status: P0 (the core) landed.** `cmd`/`args`/`argv`, `Create`/`Destroy`,
> `buildArgv`, `addArg`, `clearArgs`, `argv`, `run`, `lastRc` and `mapRc` have
> real bodies; the five **sinks** (`each`, `toArray`, `toList`, `first`,
> `count`) are **stubs until P1** — they answer rc 2 and the funcs among them
> answer the `__TUTIL_PENDING__` sentinel. Suite: `tests/001_Core.sh`,
> **59 checks green on bash 5.2.37 and on bash 5.3.9**. Design record and phase
> history: [PLAN.md](PLAN.md) / [tutil_ledger.json](tutil_ledger.json).

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
u.delete
```

What that buys over calling the tool by hand:

1. **Typed options → an argv ARRAY, no string building.** No `eval`, no word
   splitting; a path with a space, or a pattern that starts with `-`, is safe by
   construction.
2. **One rc convention.** grep's 0/1/2, sed's 0/1/2/4 and find's 0/1 all collapse
   onto kcl `README.md` §1.2 through `mapRc`, while the raw status stays
   readable through `lastRc`.
3. **The sinks** (P1) — `each`, `toArray`, `toList`, `first`, `count` on every
   wrapper, all delegating to [`TPipe`](../tpipe/README.md), so a wrapper is a
   producer that composes with real pipes *and* with the safe `--` form.
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
| `crlf` | var | `1` → the P1 sinks strip ONE trailing CR per record (`TPipe -c`) | — |
| `nul` | var | `1` → records are NUL-terminated (`TPipe -0`) | — |
| `_lastRc` | var | raw rc of the last `run`/sink; `-1` until one ran | — |
| `buildArgv` | func | **virtual.** Fills `${inst}_argv`. Base: `cmd` + the extras | word count |
| `addArg ARG...` | proc | append to `${inst}_args` — the un-modelled-option hatch | — |
| `clearArgs` | proc | empty `${inst}_args` | — |
| `argv NAME` | func | `buildArgv`, then **copy** into the caller's array. Runs nothing | word count |
| `run` | proc | execute the argv in the foreground, **stdout inherited** | — |
| `lastRc` | func | the raw exit status of the last `run`/sink | that status |
| `mapRc RAW` | func | **virtual.** Normalise a raw status. Base: `0`→0, `127`→1 + one debug line, else 1 silent | the mapped rc |
| `each CB` | proc | **P1** — `TPipe.each [-0] [-c] CB -- "${argv[@]}"` | *(stub: rc 2)* |
| `toArray NAME` | func | **P1** — `TPipe.toArray …` | *(stub: `__TUTIL_PENDING__`)* |
| `toList INST` | func | **P1** — `TPipe.toList …` | *(stub: `__TUTIL_PENDING__`)* |
| `first` | func | **P1** — `TPipe.first …` | *(stub: `__TUTIL_PENDING__`)* |
| `count` | func | **P1** — `TPipe.count …` | *(stub: `__TUTIL_PENDING__`)* |

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
| `argv NAME` with a bad output name | **2** | `''` | one line under the switch |
| `buildArgv` / `argv` succeeded | 0 | the word count | — |
| `lastRc` | 0 | the raw status, `-1` if nothing ran | — |
| `mapRc RAW` | 0 | the mapped rc (`0` or `1`) | one line for `127` |

A diagnostic reaches stderr **only** under `VERBOSE_KKLASS=debug`
(`kk.debug`). rc 2 paths **run nothing**: the tool is not started and stdin is
not touched — a here-string handed to a refused call is still fully readable
afterwards.

**A missing command is pre-checked.** `run` asks `command -v -- "$cmd"` (a
builtin, no fork) before executing, because bash's own `command not found` line
goes to stderr *unconditionally* and would be attributed to `kklass.sh`. This is
deliberately stricter than `TPipe`, which takes an arbitrary argv and cannot
know the command; `TUtil` owns `cmd`, so it can check it.

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

## 3. Reserved member names

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

## 4. Writing a descendant

```bash
class TMyTool : TUtil
    public
        var someOption
        constructor Create
        override func buildArgv
        override func mapRc
end
```

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

---

## 5. Tests

```bash
bash kcl/tutil/tests/tests.sh                  # 5.2.37
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe kcl/tutil/tests/tests.sh
```

| File | Cases | What it pins |
|---|---|---|
| `001_Core.sh` | 59 | source integrity; the lifecycle (every var present in `${inst}_data` with its default, both arrays created and freed, every var readable under `set -u`); the argv model (`--format=%H` verbatim, `addArg`/`clearArgs`, `argv` is a copy and runs nothing, rebuild without accumulation); `argv`'s out-name validation (11 refusals, each rc 2 with `RESULT=''` and storage intact); `run` (cmd `''` runs nothing and leaves a here-string unread; a missing command is rc 1 + `lastRc` 127 + exactly one stderr line under the switch and none without; a tool exiting 3 is rc 1 + `lastRc` 3 and silent; two instances keep separate `_lastRc`); byte-identity of the stream in all three positions, including a producer emitting `-n`, a backslash, a glob, a CR and an unterminated tail; `mapRc`'s base table; the `set -eu` contract including a failing and a missing tool |
| `002_Sinks.sh` | *P1* | the five sinks against `TPipe` called directly |
| `003_Contract.sh` | *P1* | the full `set -eu` / debug-switch contract file |
