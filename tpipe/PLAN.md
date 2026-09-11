# TPipe — stream-to-callback adaptor plan (kcl/tpipe)

**Status: PLANNED, critic-hardened (2026-09-10). No code yet.** Owner accepted the
design and the recommended defaults D1–D5 (§2.0). A critic pass (§8) found 2
blockers and 8 majors in the first draft; every one is folded into the sections
below, so the worker reads the sections, not §8. One new decision, **D6**, is
recorded with the supervisor's choice and flagged to the owner.

**Roadmap position:** owner request 2026-09-10, ahead of fpjson P1; TPipe lands
FIRST, `tutil` (the wrapper base) and `tgrep` (the first wrapper) build on it.
**Source of truth:** none in FPC — this is a **kcl addition** (like
`tfile.readAllTextVar`), born from a bash fact: the right-hand side of `|` is a
subshell, so `producer | obj.method` throws away every mutation `obj.method` makes.
**Target:** `kcl/tpipe/tpipe.sh` — kklass Pascal-DSL **static** class `TPipe`
(model: `tpath`/`tfile` — `static proc` + a unit-local `tpipe._ret`, no `static var`,
so the class keeps kklass's thin dispatcher).
**Ledger:** `kcl/tpipe/tpipe_ledger.json`.
**Workflow:** phase → dual-bash tests → full master sweep → STOP → "go"; commits
gated; no unit edits during a sweep. Supervisor mode as in
`kcl/thashset/SESSION_PROMPT.md`: an Opus worker implements a phase, the reviewing
session verifies against the live tree, commits, starts the next phase.
**Conventions:** `kcl/README.md` §1 in full (RESULT/rc, `kk.debug`, rc 2 for a
malformed call, `kk._outName`, `set -eu`, locale self-heal, no forks per element,
`__tpi_` local prefix — `__tp_` is tpath's, `__tf_` tfile's; `TPipe.`/`tpipe.`/
`__TPIPE_` have zero hits in the repo today).

---

## 1. Scoping analysis

### 1.1 The problem, measured (2026-09-10, bash 5.2.37 msys and 5.3.9 cygwin)

| form | object state after 3 lines |
|---|---|
| `printf 'a\nb\nc\n' \| c.onLine` | **lost** (n=0) |
| `d.onLine < <(printf …)` | kept (n=3) |
| `shopt -s lastpipe; printf … \| e.onLine` | kept (n=3) |

Facts every design line below depends on — all verified on both bashes, and each
one becomes a pinned test (§3):

- `BASH_SUBSHELL` is **1** inside the RHS of a pipe, inside `$( )` and inside a
  `<( )` body, and **0** under `lastpipe` — *including when the frame is a kklass
  static member* (the thin dispatcher adds two function frames and no subshell).
  `lastpipe` applies when the last pipeline element is a kklass static member, and
  `PIPESTATUS` is correct there.
- `exec {fd}< <(cmd); pid=$!` captures the producer pid immediately; `exec {fd}<&-`
  closes the stream on demand; `wait "$pid"` returns the producer's real rc (4 → 4,
  a shell-function producer 6 → 6, a missing command 127). `$!` clobbered by a
  callback that starts a job does NOT affect the captured pid. Waiting twice on the
  same pid returns the same rc; an earlier pending procsub does not interfere.
- Closing the fd on an infinite producer (`yes`) kills it with SIGPIPE (rc 141). A
  producer that **ignores SIGPIPE and keeps writing** exits on its own; one that
  ignores SIGPIPE and **stops writing** (`trap '' PIPE; echo a; sleep 8`) blocks
  `wait` for its whole remaining life (8.1 s measured) — hence the `kill -TERM` in
  §2.3, after which `wait` returns in ~50 ms with rc 143.
- `read -r -d '' -u fd` delivers NUL-delimited records, including ones containing
  newlines and an unterminated final one. A record containing a NUL byte cannot be
  held in a bash variable at all (`a\0b` arrives as `ab`) — tfile's carve-out.
- `mapfile -t -u fd ARR` fills an array from the fd with zero per-record overhead
  and delivers an unterminated last record identically on both bashes.
- Calling `b.onLine` from inside a static member keeps `b`'s state, whether the
  sink is called from top level or from inside another instance member; `this`/
  `__inst__` resolve to the *callback's* instance.
- kklass dispatch costs: a plain function call 6.8/6.5 µs, a static member 30/22
  µs, an **instance member 200/167 µs** (5.2.37 / 5.3.9). That last number is the
  price of `TPipe.each r.onLine` per record and is kklass's, not TPipe's (§2.6).

### 1.2 What TPipe is

A **sink**: it runs a producer (an argv, never a string), reads its output record by
record in the **calling shell**, and hands each record to a callback that may be a
plain function, an instance member (`r.onLine`) or a static member. It knows nothing
about grep; `tutil`'s wrappers delegate their sinks to it, and any command works
without a wrapper (`find`, `git log`, a kklass static member that streams).

### 1.3 Surface (final — changes need an owner decision)

```bash
TPipe.each  [-0] [-c] CB      [-- CMD ARG...]   # cb RECORD per record, in this shell
TPipe.toArray [-0] [-c] NAME  [-- CMD ARG...]   # replace caller array (§1.7 contract)
TPipe.toList  [-0] [-c] INST  [-- CMD ARG...]   # INST.Add RECORD per record (duck-typed)
TPipe.first   [-0] [-c]       [-- CMD ARG...]   # RESULT = first record, stops producer
TPipe.count   [-0] [-c]       [-- CMD ARG...]   # RESULT = number of records
TPipe.stop                                       # inside a callback: stop after this record
TPipe.lastRc                                     # RESULT = raw rc of the last `--` producer
```

- `-0` — records are NUL-terminated (`find -print0`, `grep -lZ`), read with `-d ''`.
- `-c` — strip ONE trailing `\r` from each record (CRLF sources that keep the CR:
  `cat`, `head`, a bash-function producer; GNU grep/sed/awk strip it themselves on
  this platform, see tutil PLAN §2.6). Off by default: records are data. The letter
  is "CR", not "command"; `--` is the only producer boundary so there is no clash.
- Flags come first, are single-letter, and stop at the first non-flag word. After
  the sink's operand (CB / NAME / INST) the **only** legal next word is `--`;
  anything else is rc 2 — that is what catches a flag written after the operand.
- **The callback is invoked as `CB RECORD`** — one argument, so `printf '%s\n'`,
  `echo`-free helpers and one-argument members all work unchanged. The 1-based
  ordinal of the current record within this sink call is readable from the
  callback as **`TPIPE_INDEX`** (a `local` of the sink frame, so nested sinks each
  see their own; the tregex `RESULT_INDEX` naming). `toList`'s `.Add` gets only the
  record.
- **`--` present** → the words after it are the producer argv, run through
  `exec {fd}< <("${argv[@]}")`. No `eval`, no string splitting, ever.
- **`--` absent** → the producer is **stdin**. Allowed only when the member runs in
  the calling shell: `(( BASH_SUBSHELL > 0 ))` → **rc 2**, `RESULT=""`, nothing
  read, one `kk.debug` line (decision **D1**, message pinned in §2.5). A stdin form
  outside any pipe (`TPipe.each cb < file`) is fine (`BASH_SUBSHELL` is 0).
- **stdin passes through untouched, both ways.** The process substitution inherits
  the caller's stdin, so a producer given no file operand (`-- grep needle`,
  `-- cat`, `-- sort`) reads whatever the *caller's* stdin is — including the pipe
  in `producer | TPipe.each cb -- other` (measured). TPipe does not redirect it: a
  caller who wants the producer fed from a file redirects inside a wrapper function
  named as CMD; one who wants it silenced writes `-- sh -c 'cmd </dev/null'`.

Three ways the same job reads, which the README leads with:

```bash
shopt -s lastpipe                                  # once, top of a NON-interactive script
TGrep.search "needle" src/ | TPipe.each r.onLine   # 1. real pipe (search implies -r)
TPipe.each r.onLine -- TGrep.search "needle" src/  # 2. no shell pipe, safe anywhere
g.each r.onLine                                    # 3. sugar on a tutil wrapper
```

### 1.4 Not in scope (wontfix or deferred, with reasons)

1. **A comma / string command form** (`TPipe.call "grep x", cb`) — a comma is not a
   separator in bash and a command-as-string needs `eval`; refused for the same reason
   kcl §1.5 exists.
2. **A literal `'|'` token** (`TPipe.run cmd '|' cb`) — an unquoted `|` degrades
   silently to the lossy real pipe. A trap worse than the one being fixed.
3. **Setting `shopt -s lastpipe` from the unit** — a global shell option changed behind
   the caller's back, and inert while job control is on (interactive shells). Detect
   and refuse instead (D1).
4. **Multi-stage pipelines in the `--` form** (`-- a -- b`) — the real `|` under
   lastpipe already composes any number of stages; the `--` form is single-producer.
5. **A callback-per-field / awk-style splitter** — that is `tstringhelper.split` on the
   record inside the callback; not TPipe's job.
6. **Timeouts on the producer.** TPipe never times a producer out. `TPipe.first --
   cat`, `-- sleep 30`, `-- ssh host tail -f` block in `read` until the producer
   writes or exits (measured: a `sleep 30` producer blocks `first` until killed).
   `timeout(1)` in the argv (`-- timeout 5 cmd`) is the tool; it exists on both
   targets and kills the whole procsub tree.
7. **stderr capture** — the producer's stderr passes through untouched (unix). A
   caller that wants it redirects it in a wrapper function that it names as CMD.
8. **Records containing NUL** — a bash limitation (§1.1); documented next to tfile's.
9. **A `-0`-aware `first`/`count` that also splits on `\n`** — one delimiter per call.

---

## 2. Design decisions

### 2.0 Owner decisions

| ID | Decision |
|---|---|
| **D1** (owner, 2026-09-10) | stdin form in a subshell (`cmd \| TPipe.each cb` without lastpipe, or under `$( )`) is **refused**: rc 2, `RESULT=""`, nothing read, `kk.debug` names the fixes. Silent state loss is worse than a refusal. |
| **D2** (owner) | early stop is an explicit **`TPipe.stop`** call from inside the callback; the callback's own rc is **ignored** (a §1.3 predicate legitimately returns rc 1 and must not tear the stream). |
| **D3** (owner) | names: `TPipe` (this unit), `TUtil` for the wrapper base, `TGrep` for the first wrapper. |
| **D4** (owner) | first-wave wrappers target **GNU** tools as shipped by MSYS2; no BSD/macOS layer. Affects tutil. |
| **D5** (owner) | TPipe is a **kcl unit** (`kcl/tpipe`, own tests, own README, kcl README §2 row), not a kkore helper. |
| **D6** (supervisor, flagged) | The `--` form under `BASH_SUBSHELL > 0` (`x=$(TPipe.each r.onLine -- cmd)`, `( … )`, a pipe RHS) also loses an instance callback's mutations and a `toArray` nameref fill (measured). The critic proposed refusing the three mutating sinks there. **Chosen: allowed, with one `kk.debug` line** — because `out=$(TPipe.each fmt -- cmd)` with a *plain* formatting function is a legitimate stateless use and the `$( )` there is the caller's own explicit choice, unlike the accidental subshell of `\|` that D1 covers. The README names the trap in the D1 paragraph. Owner may flip this to rc 2 before P0 starts. |

### 2.1 One reader, five sinks

All five sinks share one private engine, `tpipe._open`/`tpipe._close` around a
reader loop, so the flag parser, the guards, the pid capture and the rc bookkeeping
exist once:

```
tpipe._open  FLAGS... [-- CMD...]   -> __tpi_fd, __tpi_pid ('' = stdin), __tpi_d, __tpi_crlf; rc 2 on D1 / bad flag
tpipe._close [stopped]              -> exec {__tpi_fd}<&- when we opened it; [kill -TERM]; wait -> __TPIPE_RC
```

The engine is plain functions (`tpipe._*`), never class members — the tfile/tpath
pattern, so the sinks share logic without a nested `$( )`.

### 2.2 The reader loop

```bash
# Record delimiter as a VALUE, never as an option word built by expansion:
# `${d:+-d ''}` is split by the CALLER's IFS, not by the `IFS=` prefix, so a
# caller with IFS=':' turns `-d ''` into one word and the delimiter silently
# becomes a space (measured, both bashes: 'a\0b\0' came back as ONE record 'ab').
local __tpi_d=$'\n'                 # -0 sets __tpi_d=''  (NUL)
local __TPIPE_STOP=0 TPIPE_INDEX=0
while IFS= read -r -d "$__tpi_d" -u "$__tpi_fd" __tpi_line || [[ -n "$__tpi_line" ]]; do
    if [[ -n "$__tpi_crlf" ]]; then __tpi_line="${__tpi_line%$'\r'}"; fi
    TPIPE_INDEX=$(( TPIPE_INDEX + 1 ))
    "$__tpi_cb" "$__tpi_line" || :
    if (( __TPIPE_STOP )); then break; fi
done
```

- `IFS= read -r` and the `|| [[ -n ]]` tail: a last record without a terminator is
  delivered, whitespace and backslashes are verbatim; the tail cannot run away
  because `read` clears the variable at EOF; a final *empty* record after a
  terminator is delivered too.
- Zero forks per record; the only fork per call is the producer itself (§1.8 allows
  an external tool once per call).
- The callback runs in **this** shell frame: it sees and may mutate its own object,
  globals, the caller's arrays. It also sees TPipe's `__tpi_*` locals dynamically;
  they are reserved names and nothing else.
- The callback's rc is discarded (D2). The loop does not read `RESULT` or `REPLY`
  between iterations, so a callback that sets them cannot derail it.

### 2.3 Stop, and what happens to the producer

Every sink opens its frame with `local __TPIPE_STOP=0`. `TPipe.stop` assigns
`__TPIPE_STOP=1`; bash's **dynamic** scoping makes that assignment land in the
innermost sink frame on the call stack, whatever depth of callbacks and nested sinks
lies between. Measured on both bashes:

- a stop inside a callback stops the innermost active sink and nothing else;
- an inner sink cannot clear an outer sink's pending stop — each frame has its own
  slot (the first draft's global-flag-reset-on-exit design lost an outer stop
  requested before an inner sink ran: 4 of 4 records instead of 2);
- a stray `TPipe.stop` outside any sink writes the process-wide `__TPIPE_STOP`
  (declared `0` at load so `set -u` is happy), which no sink ever reads;
- no reset-on-exit is needed; frames unwind on their own.

`TPipe.stop` leaves `RESULT` untouched — it is called from inside a callback that
may be mid-computation.

`tpipe._close` takes one of two paths:

- **Normal EOF** (the reader ran out): `exec {fd}<&-`, then
  `__TPIPE_RC=0; wait "$pid" || __TPIPE_RC=$?` — the producer's real rc.
- **Consumer-initiated stop** (`TPipe.stop`, or `first` after its record):
  `exec {fd}<&-` first, so a SIGPIPE-honouring producer dies on its own (rc 141);
  then `kill -TERM "$pid" 2>/dev/null || :`; then the same guarded `wait`. Without
  the `kill`, a producer that ignores SIGPIPE and does not write again blocks `wait`
  for its whole remaining lifetime (8.1 s measured for `trap '' PIPE; echo a; sleep
  8; echo b`); with it, `wait` returns in ~50 ms with rc 143 and the producer's own
  children are gone. `kill -- -"$pid"` is wrong: a process substitution is not a
  process-group leader (rc 1, measured).

`__TPIPE_RC` is therefore 141 (SIGPIPE), 143 (SIGTERM) or the producer's own rc, and
the **member's** rc is 0 whenever the consumer stopped the stream — that is the
consumer's success, not the producer's failure.

### 2.4 Return contract per sink

| member | RESULT | rc 0 | rc 1 (silent) | rc 2 (malformed call, `kk.debug`) |
|---|---|---|---|---|
| `each` | records delivered | producer rc 0, or stopped | producer rc ≠ 0 (grep "no match" = 1 lands here naturally) | CB not a function (`declare -F` up front, like `THashSet.onNotify` `thashset.sh:638` — **not** `THashSet.ForEach` `:409`, which answers rc 1 for the same condition); bad flag; word after CB that is not `--`; D1 |
| `toArray` | records stored (the array is **replaced**, `mapfile` clears it first) | same | same | NAME fails `kk._outName NAME __tpi_ __TPIPE_ TPIPE_INDEX` (the third prefix because every sink shadows `TPIPE_INDEX` with a `local`, so a nameref to that name would fill the sink's own slot and the caller would silently get nothing), or is currently an **associative** array, **integer-attributed** (`declare -i`: `mapfile` "succeeds" and evaluates every record arithmetically, `abc` → `0`) or **readonly** (`mapfile` into either prints a bash diagnostic and returns 1 — measured; an existing scalar is converted and fine); bad flag; D1 |
| `toList` | records **offered** to `INST.Add` (its rc is ignored with `\|\| :` — `THashSet.Add` says 1 for a duplicate, `TStringList.Add` under `dupError` too) | same | same | `declare -F "$INST.Add"` false; bad flag; D1 |
| `first` | first record, `''` if none | a record was read (producer stopped after it, §2.3) | no record | bad flag; D1 |
| `count` | records | producer rc 0 | producer rc ≠ 0 | bad flag; D1 |
| `stop` | untouched | always | — | — |
| `lastRc` | raw rc of the last **`--`** producer; **`-1`** when no sink has run yet *or* the last sink read stdin (there was no producer of ours — read `${PIPESTATUS[0]}` right after the pipeline; measured `(3 0)` under lastpipe with a static member as the last element) | always | — | — |

**Named deviation from kcl §1.2.** For the four counting/collecting sinks, rc 1
means *the producer exited non-zero*, not *no answer*: `RESULT` still carries the
records delivered, and `toArray`/`toList` still hold everything read before the
producer failed. Callers that want all-or-nothing check the member's rc (or
`TPipe.lastRc`) before using the data. This goes in `kcl/tpipe/README.md` and in
the kcl README §2 row, in the tregex/thashset format.

Further notes:

- rc 2 paths **run nothing**: the producer is not started, stdin is not touched
  (verified: a here-string is fully readable after a validation-only rc 2). This
  is why validation precedes `tpipe._open`.
- Under `$( )` the values print once (`tpipe._ret`, the tpath helper verbatim).
  `tpipe._ret` prints under **any** `BASH_SUBSHELL > 0`, which includes the RHS of
  a pipe without lastpipe: a `--`-form sink used there writes its `RESULT` into the
  pipeline's stdout (measured). This is the tpath contract verbatim; documented,
  not fixed.
- `kk._outName` refuses `${__inst__}_data/_class/_items` only when `__inst__` is
  set, i.e. when the sink is called from inside an instance member (tutil's case);
  a top-level `TPipe.toArray h_items -- cmd` is **not** refused and would replace a
  live `THashSet`'s storage. Documented boundary.
- `toList` is duck-typed on purpose: anything with an `.Add` wrapper qualifies
  (`TStringList`, `TList`, a user class), and tpipe does not source tstringlist.
- `-c` under `toArray` is one extra pass over the array after `mapfile`.

### 2.5 Argument validation order and the D1 message

1. flags (`-0`, `-c`; anything else starting with `-` that is not `--` → rc 2);
2. the sink's own operand (CB / NAME / INST) — rc 2 rules above;
3. the word after the operand must be `--` or absent → else rc 2;
4. `--` present with an **empty** argv after it → rc 2 (`TPipe.each cb --` is a
   mistake, not "read stdin");
5. `--` absent → the D1 subshell check; `--` present and `BASH_SUBSHELL > 0` → one
   `kk.debug` line, continue (D6);
6. only now `tpipe._open`.

The D1 message, pinned (004 asserts exactly one line matching it):

```
Error: TPipe.MEMBER: stdin form ran in a subshell (BASH_SUBSHELL=N); use `TPipe.MEMBER [OPERAND] -- CMD ...`, or `shopt -s lastpipe` at the top of a NON-interactive script (lastpipe is inert while job control is on)
```

`MEMBER` is the sink name and `[OPERAND]` is `CB` for `each`, `NAME` for `toArray`, `INST` for `toList`, and absent (single space) for `first`/`count`.

The D6 line, pinned the same way (one line, `Warning:` prefix, only under the switch):

```
Warning: TPipe.MEMBER: running in a subshell (BASH_SUBSHELL=N); records are delivered, but every mutation the callback makes is lost when the subshell exits
```

CMD is executed as `"${argv[@]}"` inside the process substitution: a bash function
(a kklass static member such as `TGrep.search`, a user wrapper that redirects
stderr), a builtin, or an executable — whatever `command` would find. It is not
pre-checked with `type`: the process substitution reports 127 through `wait`
(verified), which maps to rc 1 + `lastRc` 127, the same way any failing producer
does. (tutil pre-checks its own `cmd`; that is its choice, tutil PLAN §2.3.)

### 2.6 Performance model and gates

Per call: one fork (the producer) + the process-substitution plumbing; per record:
one `read`, one function call, one `(( ))`. Measured on this machine, 10 000
records, plain-function callback (5.2.37 / 5.3.9):

| path | ratio to bare bash |
|---|---|
| `TPipe.each` + no-op function vs bare `while read` | 1.18× / 1.25× |
| `toArray` vs bare `mapfile` | 1.02× / 1.01× |
| `first` on `yes` | 33 ms / 41 ms, lastRc 141 or 143 |
| forks per record | 0 |

Gate at P2, **plain-function callback**: `each` ≤ 2× the bare loop; `toArray`
(no flags) ≤ 1.5× bare `mapfile`; `first` on an infinite producer ≤ 250 ms; zero
forks per record (`$BASHPID` in the callback).

**Published separately, not gated:** an *instance-member* callback (`r.onLine`)
costs a full kklass instance dispatch — 200 µs on 5.2.37, 167 µs on 5.3.9, against
6.8/6.5 µs for a plain function — so `TPipe.each r.onLine` over 10 000 records
runs ~3× the bare loop. That is kklass's dispatch price, not TPipe's; the README
quotes it so callers with 10⁵-record streams reach for `toArray` + a loop, or a
plain-function callback that forwards to the object only when needed.

---

## 3. Pinned facts (each is a test)

| # | Fact | Test |
|---|---|---|
| F1 | RHS of `\|` is a subshell: object state lost | 001: `cmd \| TPipe.each cb` is rc 2, `RESULT=""`, callback never called, object untouched, exactly the §2.5 message under debug |
| F2 | `BASH_SUBSHELL` = 1 in the pipe RHS, 0 under lastpipe, also for a static member | 001: the same call under `shopt -s lastpipe` delivers and mutates; `PIPESTATUS[0]` is the producer's |
| F3 | `exec {fd}< <(cmd); pid=$!; …; wait $pid` = producer rc | 001: `-- sh -c 'echo a; exit 4'` → RESULT 1, rc 1, lastRc 4; a function producer `exit 6` → 6; a missing command → 127 |
| F4 | closing the fd kills an infinite producer (141), `wait` returns | 002 (P0: via `each` + `TPipe.stop`; re-pointed at `first` in P1): `TPipe.first -- yes` returns `y` in < 250 ms, lastRc 141 **or 143** (the close and the `kill -TERM` race: under load the TERM lands before `yes` attempts its next write — seen in the 5.3.9 master sweep) |
| F5 | a SIGPIPE-ignoring producer that **stops writing** is terminated | 002: producer function `trap '' PIPE; echo a; sleep 8; echo b` (stderr to /dev/null); `first` returns in < 1 s, lastRc 143; whole test under `timeout 5` |
| F6 | `$!` clobbered by a callback does not affect the captured pid | 002: callback runs `( : ) & wait $!`; lastRc still the producer's |
| F7 | `-d ''` delivers NUL records | 003: `-0 -- find … -print0` count equals a bare `mapfile -t -d ''` oracle over the same producer, and a name containing a newline round-trips byte-exact (the `-print` form OVER-counts such a name — that is what `-print0` exists for) |
| F8 | `mapfile -t -u fd` fills from the fd, unterminated tail delivered | 003: `toArray` 10k records equals a bare `mapfile`; `-- printf 'a\nb'` → 2 elements on both bashes |
| F9 | nested dispatch: `b.onLine` from inside a static member keeps `b`'s state, from top level and from inside another member | 001 |
| F10 | last record without `\n` is delivered; a final empty record after `\n` is delivered | 001: `-- printf 'a\nb'` → 2; `-- printf 'a\n\n'` → 2 |
| F11 | `read -r -d "$d"` is IFS-proof; `read -r ${d:+-d ''}` is not | 003: `IFS=':'` around a `-0` call still yields 2 records |
| F12 | stop is frame-local | 002: outer stop + inner sink in the same callback → outer 2, inner 4; stop inside the inner callback → outer 4, inner 1; stray stop → next sink runs fully |
| F13 | `TPIPE_INDEX` is 1-based per sink call and nested-safe | 001 |
| F14 | rc 2 paths run nothing and leave stdin intact | 003: here-string still fully readable after each rc 2 path |
| F15 | `toArray` refuses an associative or readonly target with rc 2 and no stderr | 003 |
| F16 | producer inherits the caller's stdin | 003: `-- cat` with an explicit `<<<` on the sink call delivers that text |

---

## 4. Parity & test model

No upstream. The oracle is bash itself: every sink's answer is compared with a bare
`while read` / `mapfile` / `head -n1` / `wc -l` over the same producer. The
exotic-record matrix (`''`, leading `-e`/`-n`, `\`, `$(…)`, `*`, `]`, a tab, a CR,
UTF-8, a 64 KiB record) runs through `each`, `toArray` and `toList` and must
round-trip byte-exact — **except NUL**, which no bash variable can hold (§1.1); the
README carries the carve-out next to tfile's.

Every test sets its own stdin explicitly (`<<<` or `< file`) and never relies on
what ktests hands the file: the runner gives a test child the terminal in
`--mode single` and `/dev/null` in the default `--mode threaded --workers 8`, and a
`-- cat` test would hang the former and read EOF in the latter.

"Nothing printed on rc 0/1" is asserted **for TPipe's own output**: the producer's
stderr passes through (§1.4 item 7), and the stop path routinely yields
`write error: Broken pipe` from the producer, so those tests give the producer
`2>/dev/null`.

Red-first: for P0 the unit file does not exist, so red is measured against the
**P0.1 skeleton** — all seven members declared with `tpipe._pending` bodies (`build`
refuses a declared member with no implementation function, verified); the counts go
in the ledger. Later phases stash the unit file.

Test files:

| file | phase | what |
|---|---|---|
| `001_Each.sh` | P0 | F1/F2/F3/F9/F10/F13, callback validation (plain fn / `r.onLine` / static member / dangling name rc 2 / word after CB rc 2), nested `each`, the README three forms with a plain function and with `r.onLine` |
| `002_Stop.sh` | P0 | F4/F5/F6/F12, `lastRc` before any sink = -1, `lastRc` after a stdin-form sink = -1 |
| `003_Sinks.sh` | P1 | `toArray`/`toList`/`first`/`count` vs bare-bash oracles, `-0`, `-c`, F7/F8/F11/F14/F15/F16, exotic matrix, the rc 1 + non-empty RESULT deviation, `toList` with a rejecting `.Add` |
| `004_Contract.sh` | P1 | loads the unit and runs all sinks under `set -eu`, both forms, including a failing producer (bare `wait` would abort the frame — measured rc 4 kills it); `VERBOSE_KKLASS=debug` prints exactly one line per rc 2 path, the D1 line verbatim; nothing from TPipe otherwise |
| `005_Bench.sh` | P2 | the §2.6 gates as assertions with ceilings ≥ 3× the measured values (ktests runs files threaded, 8 workers, by default); exact numbers come from `bench.sh` run by hand in `--mode single` |

Runner: `tests/tests.sh` → ktests, as every unit.

---

## 5. Phases

### P0 — engine + `each` + `stop` + `lastRc` (gate: 001 + 002 green on both bashes, sweep)

- P0.1 `tpipe.sh` skeleton: re-source guard, locale self-heal, `tpipe._ret`
  (tpath's, verbatim), the `TPipe` class with **all seven** members declared and
  every one given a `tpipe._pending` body (rc 2 + `kk.debug`, never `RESULT`);
  `__TPIPE_STOP=0`, `__TPIPE_RC=-1` at load. 001/002 are written against this
  skeleton for their red counts.
- P0.2 `tpipe._open` / `tpipe._close` / the flag parser / validation order §2.5 /
  the D1 guard and message / D6 debug line / pid capture / close-kill-wait per §2.3
  with every `wait` guarded.
- P0.3 `TPipe.each` per §2.2–§2.5 with `TPIPE_INDEX`; `TPipe.stop` (frame-local);
  `TPipe.lastRc`.
- P0.4 tests 001, 002; README first cut with the three forms, the D1 message
  verbatim, the D6 note and the instance-dispatch cost.

### P1 — the other sinks + flags (gate: 003 + 004 green, sweep)

- P1.1 `toArray` (`mapfile -t [-d ''] -u fd`, `kk._outName NAME __tpi_ __TPIPE_`,
  assoc/readonly refusal), `toList` (`declare -F "$INST.Add"`, `|| :` on Add),
  `first` (read one, stop path), `count`; the `-0`/`-c` flags wired through every
  sink; stub helper deleted; test that no member answers a pending sentinel any
  more.
- P1.2 tests 003, 004.

### P2 — closeout (gate: 005 green, bench numbers in README, sweep on both bashes)

- P2.1 `bench.sh` on `TStopwatch.getTimeStamp` (source `../tstopwatch/tstopwatch.sh`):
  each/no-op-function vs bare loop, each/`r.onLine` (published, not gated), toArray
  vs mapfile, first-on-yes latency, zero-fork probe; run in `--mode single`, numbers
  with the bash version in the README.
- P2.2 README final (contract table §2.4 with the named deviation, the three forms,
  D1 rationale with the measured table from §1.1, D6, the frame-local stop rule,
  stdin pass-through, the NUL carve-out, GNU/lastpipe notes), `docs/TPipe.md`
  (design record: the 2026-09-10 probes and the critic's probes as reproducible
  scripts), `TEST_COVERAGE_NOTES.md`, kcl README §2 row (kind: static, "kcl addition
  — no FPC source", the rc 1 deviation), ledger COMPLETE with SHAs.

---

## 6. Bash traps to respect

- `read` without `IFS=` strips leading/trailing blanks; without `-r` eats backslashes.
- The delimiter is passed as a value (`-d "$d"`), never as an expansion-built option
  word (§2.2, F11).
- `(( __TPIPE_STOP ))` as a statement returns 1 when 0 → always inside `if`.
- `declare -F "$cb"` ACCEPTS `--` as a callback (it is read as the end-of-options marker, rc 0, no output — measured on both bashes): the validator is `declare -F -- "$cb"`, and `_open` refuses an operand equal to `--` on its own (P0 finding).
- `exec {fd}<&-` **before** `wait`, never after — otherwise a blocked producer never
  gets its SIGPIPE and `wait` hangs; and on the stop path `kill -TERM "$pid"` between
  the two (§2.3).
- `wait "$pid"` is the one statement in the engine that is *expected* to be
  non-zero: always `__TPIPE_RC=0; wait "$pid" || __TPIPE_RC=$?` — a bare `wait`
  aborts a `set -e` caller (measured). Same guard on `"$cb" "$rec" || :` (D2) and
  `"$INST.Add" "$rec" || :`.
- Do not `wait` on a pid you did not capture; `$!` belongs to whoever last started a
  job — callbacks included (F6).
- `mapfile -d ''` needs bash ≥ 4.4 (both targets qualify); `read -d ''` returns 1 at
  EOF with the buffer filled — hence the `|| [[ -n ]]` tail.
- A `static proc` body must not end on `kk._return` — the thin dispatcher would print
  on the direct call; `tpipe._ret` only.
- **An inline `$'\r'` inside a MEMBER body is silently lost**: `build` re-creates every
  member from `declare -f` through `eval`; `declare -f` prints the pattern as `'<raw CR>'`
  and the re-parse drops the CR, so the rebuilt body strips nothing (measured on both
  bashes; P0 shipped `-c` as a no-op this way, caught at P1). Plain helpers are not
  affected. The CR therefore lives in a load-time `printf -v __TPIPE_CR '\r'` and the
  bodies spell `${__tpi_line%"$__TPIPE_CR"}`; it strips exactly one CR (verified
  `x\r\r` → `x\r`); do not use `tr` (a fork per call and it would also eat embedded
  CRs). This is a kklass-wide trap for any member body carrying `$'…'` with a control
  character.
- `local __TPIPE_STOP=0 TPIPE_INDEX=0` at the top of every sink; the globals of the
  same names exist only so `set -u` never trips on a stray `TPipe.stop`.
- kklass reserved names: `this __inst__ __class__ RESULT REPLY IFS state __kk_*`;
  tpipe adds `__tpi_*`, `__TPIPE_*` and `TPIPE_INDEX`; never bind an output array to
  any of them.
- Test files: no own `EXIT` trap (it would replace ktests' trap — see tutil PLAN §4);
  own stdin always explicit; producers on the stop path get `2>/dev/null`.

---

## 7. Deliverables

`tpipe.sh`, `tests/tests.sh` + `001`–`005`, `bench.sh`, `README.md`, `docs/TPipe.md`,
`TEST_COVERAGE_NOTES.md`, `tpipe_ledger.json` COMPLETE, kcl `README.md` §2 row.

## 8. Critic pass (2026-09-10)

An Opus critic reviewed the first draft against the live tree with 15 probe scripts
on both bashes. Findings and where each landed:

| # | sev | finding | landed in |
|---|---|---|---|
| 1 | BLOCKER | `${d:+-d ''}` is split by the caller's IFS; `IFS=':'` silently made the delimiter a space | §2.2, §6, F11 |
| 2 | BLOCKER | a SIGPIPE-ignoring producer that stops writing blocks `wait` for its whole life (8.1 s) | §2.3 close-kill-wait, F5 |
| 3 | MAJOR | global stop flag reset on exit lost an outer stop requested before an inner sink | §2.3 frame-local `local __TPIPE_STOP`, F12 |
| 4 | MAJOR | the `--` form under `$( )`/`( )`/pipe RHS also loses instance-callback state | **D6** (allowed + debug line; owner may flip to rc 2) |
| 5 | MAJOR | rc 1 with non-empty RESULT / filled array contradicts kcl §1.2 | §2.4 named deviation |
| 6 | MAJOR | perf gates measured against the wrong callback; `r.onLine` is 200/167 µs per record | §1.1, §2.6 |
| 7 | MAJOR | ktests runs threaded ×8 by default; 50 ms latency gate flakes | §4, §2.6 (250 ms, ceilings ≥ 3×) |
| 8 | MAJOR | `mapfile` into an assoc/readonly target prints a bash diagnostic | §2.4 toArray, F15 |
| 9 | MAJOR | the producer inherits the caller's stdin; tests would behave differently per runner mode | §1.3, §4, F16 |
| 10 | MAJOR | bare `wait` aborts a `set -e` caller | §2.3, §6, 004 |
| 11 | MINOR | `lastRc = 0` for the stdin form lies | §2.4 (`-1`, read `PIPESTATUS`) |
| 12 | MINOR | NUL inside a record is dropped by `read` | §1.1, §1.4 item 8, §4 |
| 13 | MINOR | producers that never write block `first`/`each` | §1.4 item 6 |
| 14 | MINOR | cited `ForEach` answers rc 1, not 2 | §2.4 citation |
| 15 | MINOR | tokens between the operand and `--` unspecified | §1.3, §2.5 step 3 |
| 16 | MINOR | D1 message named a fix that is inert under job control | §2.5 pinned text |
| 17 | MINOR | `tpipe._ret` prints in a pipe RHS for the legal `--` form | §2.4 note |
| 18 | MINOR | "red against an empty tree" is not a runnable state | §4, P0.1 |
| 19 | NIT | producer stderr on the stop path breaks "nothing printed" | §4 |
| 20 | NIT | `stop`'s RESULT unspecified | §2.3, §2.4 |
| 21 | NIT | `kk._outName`'s instance-array refusal is context-dependent | §2.4 note |
| 22 | NIT | `-c` reads as "command" | §1.3 (kept, explained) |
| 23 | NIT | no record ordinal for the callback | §1.3 `TPIPE_INDEX` (a variable, not a second positional — a second argument would break `printf '%s\n'`-style callbacks) |

Verified correct by the critic (not to be re-probed): F1–F4, F6–F10 as listed in
§3; the thin dispatcher does not interfere with `local`/`exec {fd}`/`$!`/`read -u`/
`wait`; `wait` twice on the same pid, an earlier pending procsub, `wait` on a
non-child (127); the callback matrix (plain / instance / static, from top level and
from inside another member); zero forks; one-CR strip; rc 2 leaves stdin intact;
`timeout` exists on both targets and kills the procsub tree; no fd leak across
open/close cycles; no name collisions with the DSL or kklass keyword lists;
`RESULT=-1` precedent; per-unit `_ret` copies are house style; a missing `--`
producer reports 127 through `wait` without a pre-check.
