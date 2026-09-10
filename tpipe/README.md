# tpipe — `TPipe`, a stream-to-callback adaptor

> **Status: P0.** The engine, `TPipe.each`, `TPipe.stop` and `TPipe.lastRc` are
> implemented and tested on bash 5.2.37 and 5.3.9. `toArray`, `toList`, `first`
> and `count` are declared but still answer rc 2 ("not implemented yet"); they
> land at P1 together with the `-0`/`-c` test matrix. See `PLAN.md`.

`TPipe` is a **kcl addition** — there is no FPC class behind it. It exists
because of one bash fact:

```bash
producer | obj.onLine        # obj.onLine runs in a SUBSHELL: every mutation is lost
```

| form | object state after 3 lines |
|---|---|
| `printf 'a\nb\nc\n' \| c.onLine` | **lost** (n=0) |
| `d.onLine < <(printf …)` | kept (n=3) |
| `shopt -s lastpipe; printf … \| e.onLine` | kept (n=3) |

(measured 2026-09-10 on bash 5.2.37 msys and 5.3.9 cygwin)

`TPipe` gives that second row a name. It runs a producer — an **argv**, never a
string — reads its output record by record **in the calling shell**, and hands
each record to a callback that may be a plain function, an instance member
(`r.onLine`) or a static member. It knows nothing about the producer: `find`,
`git log`, a bash function, a kklass static member that streams — anything
`command` would find.

```bash
source kcl/tpipe/tpipe.sh

TRec.new r
TPipe.each r.onLine -- git log --format=%H     # r keeps every mutation
printf '%s\n' "$RESULT"                        # -> number of records delivered
```

---

## 1. Surface

```bash
TPipe.each  [-0] [-c] CB [-- CMD ARG...]   # call `CB RECORD` per record, in this shell
TPipe.stop                                 # from inside a callback: stop after this record
TPipe.lastRc                               # RESULT = raw rc of the last `--` producer
```

| member | state | RESULT | rc |
|---|---|---|---|
| `each` | **P0** | records delivered | 0 producer rc 0 **or stopped**; 1 producer rc ≠ 0 (RESULT kept, §4); 2 malformed call |
| `stop` | **P0** | *untouched* | always 0 |
| `lastRc` | **P0** | raw rc of the last `--` producer, `-1` if there was none | always 0 |
| `toArray` | *pending (P1)* | — | 2 + `kk.debug` |
| `toList` | *pending (P1)* | — | 2 + `kk.debug` |
| `first` | *pending (P1)* | — | 2 + `kk.debug` |
| `count` | *pending (P1)* | — | 2 + `kk.debug` |

Flags:

* **`-0`** — records are NUL-terminated (`find -print0`, `grep -lZ`).
* **`-c`** — strip **one** trailing `\r` from each record. The letter is "CR",
  not "command". Off by default: records are data. CRLF sources that keep the CR
  are `cat`, `head` and bash-function producers; GNU grep/sed/awk strip it
  themselves on this platform.

Flags come first, are single-letter, and stop at the first non-flag word. After
the callback the **only** legal next word is `--`; anything else is rc 2 — which
is what catches a flag written after the operand:

```bash
TPipe.each cb -c -- cat file        # rc 2: the flag belongs BEFORE cb
TPipe.each -c cb -- cat file        # right
```

`TPIPE_INDEX` is readable from the callback as the **1-based ordinal** of the
current record within this sink call. It is a `local` of the sink frame, so a
nested sink started from inside a callback has its own and neither disturbs the
other; sourcing the unit also declares it globally as `0`, so a shared callback
that reads the ordinal is safe to call outside a sink under `set -u`.

The callback is invoked as **`CB RECORD`** — one argument, so `printf '%s\n'`,
one-argument members and echo-free helpers all work unchanged. **Its exit status
is ignored** (decision D2): a predicate callback legitimately answers rc 1 and
must not tear the stream down.

---

## 2. The three forms

```bash
shopt -s lastpipe                                  # once, top of a NON-interactive script
TGrep.search "needle" src/ | TPipe.each r.onLine   # 1. real pipe  (needs lastpipe)
TPipe.each r.onLine -- TGrep.search "needle" src/  # 2. no shell pipe, safe anywhere
g.each r.onLine                                    # 3. sugar on a tutil wrapper (not yet)
```

Form 3 belongs to `tutil`/`TGrep`, which are not written yet; forms 1 and 2 are
pinned against each other in `tests/001_Each.sh` §I, with a plain function and
with an instance member.

**`--` present** → the words after it are the producer argv, run through
`exec {fd}< <("${argv[@]}")`. No `eval`, no string splitting, ever. `--` with an
empty argv after it is rc 2, not "read stdin".

**`--` absent** → the producer is **stdin** (`TPipe.each cb < file`,
`TPipe.each cb <<< "$s"`, or the left-hand side of a pipe under `lastpipe`).

**stdin passes through untouched, both ways.** The process substitution inherits
the caller's stdin, so a producer given no file operand (`-- grep needle`,
`-- cat`, `-- sort`) reads whatever the *caller's* stdin is. TPipe never
redirects it: a caller who wants the producer fed from a file redirects inside a
wrapper function named as `CMD`; one who wants it silenced writes
`-- sh -c 'cmd </dev/null'`.

---

## 3. D1 — the stdin form is refused inside a subshell

The stdin form only works when the member runs in the **calling** shell. In a
subshell — the right-hand side of a pipe without `lastpipe`, `$( )`, `( )` —
every mutation the callback makes dies with the subshell. Silent state loss is
worse than a refusal, so TPipe refuses: **rc 2, `RESULT=""`, nothing read, the
callback never called**, and under `VERBOSE_KKLASS=debug` exactly one line:

```
Error: TPipe.each: stdin form ran in a subshell (BASH_SUBSHELL=1); use `TPipe.each CB -- CMD ...`, or `shopt -s lastpipe` at the top of a NON-interactive script (lastpipe is inert while job control is on)
```

`lastpipe` is worth knowing: it makes the last element of a pipeline run in the
current shell, it applies to a kklass static member, and `PIPESTATUS` is correct
there. It is **inert while job control is on**, i.e. in an interactive shell —
which is why the message names the `--` form first. TPipe never sets it for you:
that would be a global shell option changed behind the caller's back.

### D6 — the `--` form in a subshell is allowed, with a warning

`x=$(TPipe.each fmt -- cmd)` loses an instance callback's mutations for the same
reason, but that subshell is the caller's own explicit choice and a *stateless*
formatting callback is a legitimate use. So the `--` form is **allowed** in a
subshell and prints one `kk.debug` line:

```
Warning: TPipe.each: running in a subshell (BASH_SUBSHELL=1); records are delivered, but every mutation the callback makes is lost when the subshell exits
```

One consequence to know about: `tpipe._ret` prints `RESULT` under **any**
`BASH_SUBSHELL > 0`, which includes the right-hand side of a pipe without
`lastpipe`. A legal `--`-form sink used there writes its record count into the
pipeline's stdout. That is the tpath contract verbatim (kcl `README.md` §1.1),
documented rather than fixed.

---

## 4. Return contract, and one named deviation

**Named deviation from kcl `README.md` §1.2.** For `each`, rc 1 means *the
producer exited non-zero*, not *no answer*: **`RESULT` still carries the number
of records delivered**, and everything the callback did before the producer
failed still happened. Callers who want all-or-nothing check the member's rc (or
`TPipe.lastRc`) before using the data.

```bash
TPipe.each cb -- grep needle file   # no match: rc 1, RESULT=0 — grep's own 1
TPipe.each cb -- some_failing_cmd   # rc 1, RESULT=<records read before it died>
TPipe.lastRc                        # RESULT = 1 / 2 / 127 / … — grep's raw rc
```

`TPipe.lastRc` is the raw exit status of the last `--` producer, and **`-1`**
when there was no producer of ours: before any sink has run, and after a
stdin-form sink. For the stdin form read `${PIPESTATUS[0]}` immediately after the
pipeline instead.

rc 2 is a malformed **call** and those paths **run nothing**: the producer is not
started and stdin is not touched. `each` answers rc 2 for

* a callback that is not a function (checked with `declare -F` up front),
* an unknown flag, or a flag written after the callback,
* any word other than `--` after the callback,
* `--` with no producer command,
* the D1 subshell refusal.

---

## 5. Stopping early

There is no "callback returns false to stop": the callback's rc is data (D2).
Stopping is an explicit call:

```bash
onLine() {
    printf '%s\n' "$1"
    if [[ "$TPIPE_INDEX" == "10" ]]; then TPipe.stop; fi
}
TPipe.each onLine -- find . -type f
```

* the record that asked for the stop is **fully processed**; the loop breaks
  after the callback returns;
* a stopped sink is **rc 0** — that is the consumer's success, not the producer's
  failure — and `RESULT` counts the records delivered;
* `TPipe.stop` leaves `RESULT` untouched (the callback may be mid-computation);
* **the stop is frame-local.** Each sink owns a `local __TPIPE_STOP`, so a stop
  requested from any depth of callbacks lands in the innermost *active* sink; an
  inner sink cannot clear an outer sink's pending stop, and a stray `TPipe.stop`
  outside any sink is inert;
* on the stop path the producer is closed, then `kill -TERM`ed, then waited for.
  A SIGPIPE-honouring producer usually dies of the close (`TPipe.lastRc` → 141),
  but which of the two signals reaches it first is a **race**: if it did not
  attempt a write between the close and the kill, it dies of the `TERM` (→ 143)
  instead — both are correct and neither is worth asserting. A producer that
  ignores SIGPIPE and stops writing needs the `TERM` (→ 143) — without it `wait`
  blocks for the producer's whole remaining life (8.1 s measured for
  `trap '' PIPE; echo a; sleep 8; echo b`). For a short producer that had already
  finished, `lastRc` after a stop is simply its own rc, so `lastRc` is only
  meaningful on the stop path as "141 / 143 / whatever the producer managed".

---

## 6. Cost

Per call: one fork (the producer) plus the process-substitution plumbing. **Per
record: zero forks** — one `read`, one function call, one arithmetic expansion
(pinned with a `$BASHPID` probe).

| path | ratio to bare bash (5.2.37 / 5.3.9) |
|---|---|
| `TPipe.each` + a no-op **function** vs a bare `while read` | 1.18× / 1.25× |

**An instance-member callback is a different order of magnitude, and it is
kklass's price, not TPipe's.** kklass dispatch costs 6.8/6.5 µs for a plain
function, 30/22 µs for a static member and **200/167 µs for an instance member**,
so `TPipe.each r.onLine` over 10 000 records runs roughly 3× the bare loop.
Callers with 10⁵-record streams should reach for `toArray` + a plain loop (P1),
or for a plain-function callback that forwards to the object only when it must.

(The numbers above are the design measurements from `PLAN.md` §1.1/§2.6;
`bench.sh` and the gate assertions land at P2.)

---

## 7. Limits

* **A record containing a NUL byte cannot be delivered.** No bash variable can
  hold one (`a\0b` arrives as `ab`) — the same carve-out `tfile` documents. `-0`
  is about the *delimiter*, not about NULs inside a record.
* **TPipe never times a producer out.** `-- cat`, `-- sleep 30`, `-- ssh host
  tail -f` block in `read` until the producer writes or exits. `timeout(1)` in
  the argv (`-- timeout 5 cmd`) is the tool; it exists on both targets and kills
  the whole process-substitution tree.
* **The producer's stderr passes through untouched.** A caller who wants it
  captured redirects it inside a wrapper function named as `CMD`. On the stop
  path a producer routinely prints `write error: Broken pipe`; that is the
  producer's output, not TPipe's.
* **Single producer.** `-- a -- b` is not a pipeline; a real `|` under `lastpipe`
  already composes any number of stages.
* **Reserved names.** `__tpi_*`, `__TPIPE_*` and `TPIPE_INDEX` belong to this
  unit, on top of kklass's `this __inst__ __class__ RESULT REPLY IFS state
  __kk_*`. Never bind an output array to any of them.

---

## 8. Tests

```bash
bash kcl/tpipe/tests/tests.sh                  # 5.2.37
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe kcl/tpipe/tests/tests.sh
```

| file | what it pins |
|---|---|
| `001_Each.sh` | the producer's real rc through `wait` (F3), delivery and the unterminated/empty tail (F10), records as data (the exotic matrix), `TPIPE_INDEX` (F13), the callback matrix — plain / instance / static, from top level and from inside another member (F9), every rc 2 path, the D1 refusal and its pinned message (F1), `lastpipe` (F2), the two README forms, D6 |
| `002_Stop.sh` | the close-kill-wait path on an infinite producer (F4) and on a SIGPIPE-ignoring one (F5), `$!` clobbered by a callback (F6), the frame-local stop in all four shapes (F12), `stop` leaves `RESULT` alone, `lastRc` sentinels |

`003_Sinks.sh`, `004_Contract.sh` and `005_Bench.sh` arrive with P1 and P2.
