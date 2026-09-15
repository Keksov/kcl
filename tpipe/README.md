# tpipe — `TPipe`, a stream-to-callback adaptor

> **Status: COMPLETE (P0–P3).** All seven members — `each`, `toArray`, `toList`,
> `first`, `count`, `stop`, `lastRc` — have real bodies, the `-0`/`-c`/`-s` flags
> are wired through every sink, the owner's **D6 final** ruling of 2026-09-15 is
> in (§3: nothing is refused because of a subshell; one `kk.warn` line where the
> loss is certain; `each` never prints), and the suite is **190 checks, green on
> bash 5.2.37 and on bash 5.3.9**. Design record and the measurements the unit is built on:
> [docs/TPipe.md](docs/TPipe.md). What the tests pin, case by case:
> [TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md). Numbers: `bench.sh`
> (summarised under [*Performance*](#6-performance) below). History: `PLAN.md` /
> `tpipe_ledger.json`.

`TPipe` is a **kcl addition** — there is no FPC or Delphi class behind it. It
exists because of one bash fact:

```bash
producer | obj.onLine        # obj.onLine runs in a SUBSHELL: every mutation is lost
```

| form | object state after 3 lines |
|---|---|
| `printf 'a\nb\nc\n' \| c.onLine` | **lost** (N=0) |
| `d.onLine < <(printf …)` | kept (N=3) |
| `shopt -s lastpipe; printf … \| e.onLine` | kept (N=3) |

(measured 2026-09-10 on bash 5.2.37 msys and 5.3.9 cygwin, re-run at P2; the
script is [docs/TPipe.md §1](docs/TPipe.md#1-the-problem-the-right-hand-side-of--is-a-subshell))

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

…and, when a callback is more machinery than the job needs, the same engine
answers with an array, a list, a first record or a count:

```bash
declare -a shas
TPipe.toArray shas -- git log --format=%H      # RESULT = ${#shas[@]}
TPipe.toList  l    -- git log --format=%H      # l.Add per record; RESULT = offered
TPipe.first        -- git log --format=%H      # RESULT = the newest sha, producer stopped
TPipe.count        -- git log --format=%H      # RESULT = how many
```

---

## 1. Surface

```bash
TPipe.each    [-0] [-c] [-s] CB   [-- CMD ARG...]   # call `CB RECORD` per record, in this shell
TPipe.toArray [-0] [-c] [-s] NAME [-- CMD ARG...]   # REPLACE the caller's array NAME
TPipe.toList  [-0] [-c] [-s] INST [-- CMD ARG...]   # call `INST.Add RECORD` per record
TPipe.first   [-0] [-c] [-s]      [-- CMD ARG...]   # RESULT = the first record, then stop
TPipe.count   [-0] [-c] [-s]      [-- CMD ARG...]   # RESULT = the number of records
TPipe.stop                                          # from inside a callback: stop after this record
TPipe.lastRc                                        # RESULT = raw rc of the last `--` producer
```

| member | RESULT | rc |
|---|---|---|
| `each` | records **delivered** — **never printed** (§3, Q7): this member's stdout is the callback's | 0 producer rc 0 **or stopped**; 1 producer rc ≠ 0 (RESULT kept, §4); 2 malformed call |
| `toArray` | records **stored** (the array is replaced) | same as `each` |
| `toList` | records **offered** to `INST.Add` | same as `each` |
| `first` | the first record, `''` if there was none | 0 a record was read (the producer's own rc is irrelevant — *we* stopped it); 1 no record; 2 malformed call |
| `count` | records **counted** | same as `each` |
| `stop` | *untouched* | always 0 |
| `lastRc` | raw rc of the last `--` producer, `-1` if there was none | always 0 |

Every one of those RESULTs **except `each`'s** is also **printed once** when the
sink runs inside a subshell — see [`__TPIPE_QUIET`](#7-traps-and-limits) in §7
for the one-line opt-out a *composing* caller (a member of your own class that
runs a sink and then answers through its own return channel) declares so that
the value is not printed twice. `each` prints nothing anywhere: its stdout
belongs to the callback (§3, decision D6 final Q7).

Flags:

* **`-0`** — records are NUL-terminated (`find -print0`, `grep -lZ`), read with
  `-d ''`.
* **`-c`** — strip **one** trailing `\r` from each record. The letter is "CR",
  not "command". Off by default: records are data. CRLF sources that keep the CR
  are `cat`, `head` and bash-function producers; GNU grep/sed/awk strip it
  themselves on this platform. `-c` is accepted by `count` for surface symmetry
  and is a no-op there — stripping a CR cannot change how many records there are.
* **`-s`** — "the subshell scope is **intended**": silences this call's subshell
  warning (§3). Accepted by every sink and inert on `first`/`count`, which never
  warn. It changes nothing else — not the rc, not `RESULT`, not what is read.

Flags come first, are single-letter, and stop at the first non-flag word. After
the sink's operand the **only** legal next word is `--`; anything else is rc 2 —
which is what catches a flag written after the operand:

```bash
TPipe.each cb -c -- cat file        # rc 2: the flag belongs BEFORE cb
TPipe.each -c cb -- cat file        # right
```

`first` and `count` take **no operand**, so for them the first non-flag word must
already be `--`:

```bash
TPipe.count -0 -- find . -print0    # right
TPipe.count -0 x -- find . -print0  # rc 2: 'x' is not '--'
```

The callback is invoked as **`CB RECORD`** — one argument, so `printf '%s\n'`,
one-argument members and echo-free helpers all work unchanged. **Its exit status
is ignored** (decision D2): a predicate callback legitimately answers rc 1 and
must not tear the stream down.

`TPIPE_INDEX` is readable from the callback as the **1-based ordinal** of the
current record within this sink call:

```bash
onLine() {
    printf '%s: %s\n' "$TPIPE_INDEX" "$1"
    if (( TPIPE_INDEX == 10 )); then TPipe.stop; fi
}
```

It is a `local` of the sink frame, so a nested sink started from inside a
callback has its own and neither disturbs the other; sourcing the unit also
declares it globally as `0`, so a shared callback that reads the ordinal is safe
to call outside a sink under `set -u`. It is a **mirror** of the sink's private
counter, so a callback that assigns to `TPIPE_INDEX` cannot corrupt `RESULT`.

---

## 2. The three forms

```bash
shopt -s lastpipe                                  # once, top of a NON-interactive script
TGrep.search "needle" src/ | TPipe.each r.onLine   # 1. real pipe  (needs lastpipe)
TPipe.each r.onLine -- TGrep.search "needle" src/  # 2. no shell pipe, safe anywhere
g.each r.onLine                                    # 3. sugar on a tutil wrapper (TGrep : TUtil)
```

Form 3 belongs to [`tutil`](../tutil/README.md), whose five sinks are one call
into this unit each; [`tgrep`](../tgrep/README.md) is the first wrapper built on it. Forms 1 and 2 are pinned against each
other in `tests/001_Each.sh` §I, with a plain function and with an instance
member; all three are pinned against each other in `tutil/tests/002_Sinks.sh`
§L. A wrapper composing a sink this way declares `local __TPIPE_QUIET=1` (§7).

**`--` present** → the words after it are the producer argv, run through
`exec {fd}< <("${argv[@]}")`. No `eval`, no string splitting, ever. `--` with an
empty argv after it is rc 2, not "read stdin". The argv is not pre-checked with
`type`: a command that does not exist reports 127 through `wait`, which lands as
rc 1 + `lastRc` 127, exactly like any other failing producer.

**`--` absent** → the producer is **stdin** (`TPipe.each cb < file`,
`TPipe.each cb <<< "$s"`, or the left-hand side of a pipe under `lastpipe`).

**stdin passes through untouched, both ways.** The process substitution inherits
the caller's stdin, so a producer given no file operand (`-- grep needle`,
`-- cat`, `-- sort`) reads whatever the *caller's* stdin is — including the pipe
in `producer | TPipe.each cb -- other`. TPipe never redirects it: a caller who
wants the producer fed from a file redirects inside a wrapper function named as
`CMD`; one who wants it silenced writes `-- sh -c 'cmd </dev/null'`.

```bash
TPipe.count -- cat <<< $'a\nb\nc'    # RESULT = 3 — the here-string reached `cat`
```

---

## 3. A sink in a subshell — D6 final

**Nothing is refused because of a subshell.** Every sink works in every
position: the calling shell, the right-hand side of a pipe without `lastpipe`,
`$( )`, `( )`, a `<( )` body. What a subshell takes away is not the *reading* —
that always works — but the *mutations*: an object the callback changed, an
array a nameref filled, a list something was added to. So TPipe reads, delivers,
and answers exactly as the contract table says, and prints **one warning line**
in the cases where the loss is certain.

That is the owner's ruling of 2026-09-15 (`PLAN.md` §2.0 **D6 final**), which
replaced decision D1 — the old `rc 2` refusal of the stdin form — and its
`kk.debug` cousin for the `--` form. The nine answers, as they read in code:

**Q1 — nothing is refused.** `producer | TPipe.each r.onLine` runs, delivers
every record and answers rc 0. The old rc 2 and its `Error:` line are gone.

**Q2 — a warning only where the loss is CERTAIN.**

| call | warns? | why |
|---|---|---|
| `each` with an **instance member** (`r.onLine`) | **yes** | the object dies with the subshell |
| `each` with a plain function | no | it may print, count into a file, or answer through the producer's stdout — none of which a subshell loses |
| `each` with a **static** member (`Class.m`) | no | same; a static class has no per-instance state to lose |
| `toArray NAME` | **yes** | the nameref fill cannot reach the caller |
| `toList INST` | **yes** | `INST.Add` mutates a list the caller will not see |
| `first` / `count` | **never** | `RESULT` *is* the answer and the caller reads it — `n=$(TPipe.count -- cmd)` is the intended spelling |

The callback kind is decided with one builtin and no fork:
`[[ $cb == *.* ]] && declare -p "${cb%%.*}_data"` — a kklass instance wrapper is
`inst.member` with a live `${inst}_data`; a static member has none.

**The two lines**, byte-exact (`PLAN.md` §2.4, asserted verbatim in
`tests/004_Contract.sh` §3). Which one you get depends on the **form**, because
that is what tells the useful fix apart. The stdin form is almost always a pipe
right-hand side:

```
Warning: TPipe.each: the instance member r.onLine runs inside a subshell (BASH_SUBSHELL=1) — the calling shell will not see it; in a pipeline use `shopt -s lastpipe` (non-interactive scripts) or the `TPipe.each CB -- CMD ...` form at top level; if the subshell scope is intended, pass -s or set KK_SUBSHELL_OK=1
```

…and the `--` form in a subshell is almost always an explicit `$( )`, where the
only fix is to move the call out:

```
Warning: TPipe.toArray: the array shas is filled inside a subshell (BASH_SUBSHELL=1) — the calling shell will not see it; move the call out of $( ) / ( ); if the subshell scope is intended, pass -s or set KK_SUBSHELL_OK=1
```

The middle clause names the operand as the caller wrote it —
`the instance member r.onLine runs`, `the array shas is filled`,
`l.Add runs` — and the suggested form carries the operand **label**
(`CB` / `NAME` / `INST`), so the advice is copy-pasteable as it stands.

**Q3/Q4 — two ways to say "I meant it", both per call.** The flag `-s` is sugar;
the dynamically scoped `KK_SUBSHELL_OK=1` is the primitive, and it is the one
that survives a wrapper:

```bash
TPipe.toArray -s shas -- git log --format=%H     # this call only
KK_SUBSHELL_OK=1 g.each r.onLine                 # reaches TPipe through TGrep/TUtil
f() { local KK_SUBSHELL_OK=1; …; }               # a whole block, ends with the frame
```

The `KK_` prefix is deliberate: the variable is kcl-wide, so any other
callback-taking member may honour it later. A `tutil` wrapper also has the
object-style spelling, `u.subshellOk = 1` ([tutil README](../tutil/README.md)).

**Q5/Q6 — one line per call, through `kk.warn`.** There is no de-duplication: a
sink called in a loop warns once per call. The line goes through the shared
helper `kk.warn` (`kkore/klib.sh`), which is the **warning** channel of
`VERBOSE_KKLASS`, not the error one — so it is printed **with the debug switch
off** (that is the point: a caller who never turns `debug` on is exactly the
caller who would lose state in silence) and is silenced corpus-wide by
`VERBOSE_KKLASS=quiet`. It changes neither the rc nor `RESULT`, and a malformed
call never reaches it: the decision is made after validation and before the
producer starts, so an rc 2 path warns about nothing.

**Q7 — `each` never prints.** `each`'s stdout belongs to the **callback**, so
composing it is byte-clean:

```bash
x="$(TPipe.each fmt -- cmd)"       # exactly what `fmt` wrote
TPipe.each fmt -- cmd | sort       # exactly what `fmt` wrote, sorted
TPipe.each cb -- cmd; n="$RESULT"  # a DIRECT call still sets RESULT to the count
```

Before the ruling both subshell positions had the record count glued on. This is
a named deviation from kcl `README.md` §1.1 for this one member, and the reason
`each` is the only member that does not go through `tpipe._ret`. The other four
sinks are unchanged, `__TPIPE_QUIET` (§7) included.

**Q8 — when a subshell is unavoidable and the state must come back.** TPipe has
nothing for this and will not grow it; the recipes are:

```bash
# 1. do the collecting at top level and process afterwards
declare -a lines
TPipe.toArray lines -- cmd            # no subshell, no warning
for l in "${lines[@]}"; do r.onLine "$l"; done

# 2. let the callback PRINT what the parent needs, and read it back
x="$(TPipe.each -s emit -- cmd)"      # `emit` writes; -s says the scope is intended

# 3. a real pipe, with the last element in this shell
shopt -s lastpipe                     # non-interactive scripts only
cmd | TPipe.each r.onLine
```

Carrying a whole *object* back out of a subshell needs a
`snapshot` / `restore` pair on the kklass side; it is on the kklass roadmap
("snapshot/restore of an instance") and deliberately not in this unit.

**Q9 — `tutil` gets `var subshellOk`.** See [tutil](../tutil/README.md).

`lastpipe` is worth knowing: it makes the last element of a pipeline run in the
current shell, it applies to a kklass static member, and `PIPESTATUS` is correct
there (`(3 0)` for a producer exiting 3 — measured). It is **inert while job
control is on**, i.e. in an interactive shell — which is why the stdin-form line
names the `--` form as well. TPipe never sets it for you: that would be a global
shell option changed behind the caller's back.

One consequence to know about: `tpipe._ret` prints `RESULT` under **any**
`BASH_SUBSHELL > 0`, which includes the right-hand side of a pipe without
`lastpipe`. A `--`-form `toArray`/`toList`/`first`/`count` used there writes its
value into the pipeline's stdout. That is the tpath contract verbatim (kcl
`README.md` §1.1), documented rather than fixed — and a caller that is
*composing* rather than consuming turns it off with `__TPIPE_QUIET` (§7).
`each` is exempt by Q7 above.

---

## 4. Return contract, and one named deviation

| member | RESULT | rc 0 | rc 1 (silent) | rc 2 (malformed call, one `kk.debug` line) |
|---|---|---|---|---|
| `each` | records delivered — **never printed** (D6 final Q7: the stdout is the callback's; a direct call reads the count from `RESULT`) | producer rc 0, or stopped | producer rc ≠ 0 | CB is not a function; bad flag; a word after CB that is not `--`; `--` with no argv |
| `toArray` | records stored (the array is **replaced**) | same | same | NAME fails `kk._outName`, or is an **associative** array, **integer-attributed** or **readonly**; the rest as above |
| `toList` | records **offered** to `INST.Add` | same | same | `INST.Add` is not a function; the rest as above |
| `first` | the first record, `''` if none | a record was read | no record | bad flag; a word where `--` belongs; `--` with no argv |
| `count` | records counted | producer rc 0 | producer rc ≠ 0 | as `first` |
| `stop` | *untouched* | always | — | — |
| `lastRc` | raw rc of the last `--` producer, `-1` if there was none | always | — | — |

A subshell is **never** an rc 2 reason (D6 final Q1); it is at most one
`kk.warn` line (§3), which changes neither the rc nor `RESULT`.

**Named deviation from kcl `README.md` §1.2.** For the four counting/collecting
sinks, rc 1 means *the producer exited non-zero*, not *no answer*: **`RESULT`
still carries the number of records**, `toArray`'s array and `toList`'s list
still hold everything read before the producer died, and everything the callback
did still happened. Callers who want all-or-nothing check the member's rc (or
`TPipe.lastRc`) before using the data.

```bash
TPipe.each cb -- grep needle file       # no match: rc 1, RESULT=0 — grep's own 1
TPipe.each cb -- some_failing_cmd       # rc 1, RESULT=<records read before it died>
TPipe.toArray out -- some_failing_cmd   # rc 1, `out` holds what did arrive
TPipe.lastRc                            # RESULT = 1 / 4 / 127 / … — the raw rc
```

`first` is the one sink that does **not** deviate: it answers rc 1 exactly when
it has no answer, and rc 0 whenever a record was read — the producer's rc is
irrelevant there, because the consumer is what ended the stream (§5). A record
that is legitimately **empty** is still a record: `rc 0` with `RESULT=''`, as
against `rc 1` with `RESULT=''` for a producer that wrote nothing.

`TPipe.lastRc` is the raw exit status of the last `--` producer, and **`-1`**
when there was no producer of ours: before any sink has run, and after a
stdin-form sink. For the stdin form read `${PIPESTATUS[0]}` immediately after the
pipeline instead.

rc 2 is a malformed **call** and those paths **run nothing**: the producer is not
started and stdin is not touched — a here-string handed to a refused call is
still fully readable afterwards.

### `toArray` — the output-array rules

The array **name** is validated before any nameref is bound (kcl `README.md`
§1.7), and the array is **replaced**, not appended to: `mapfile` clears it first.

```bash
declare -a hits
TPipe.toArray hits -- git log --format=%H   # RESULT = ${#hits[@]}
```

Refused with rc 2 (and **no** stderr of any kind):

* a name that is not a plain identifier, or one of kklass's reserved names
  (`this`, `__inst__`, `__class__`, `RESULT`, `REPLY`, `IFS`, `state`, the
  `__kk_`/`__KK_` space) or this unit's own `__tpi_*` / `__TPIPE_*` /
  `TPIPE_INDEX`;
* a name that is currently an **associative array**, **readonly** or
  **integer-attributed**. The first two make `mapfile` print a bash diagnostic
  and return 1 (measured on both bashes), and a kcl unit never emits one. The
  third is worse than a diagnostic: `mapfile` into a `declare -i` target
  **succeeds silently** and evaluates every record arithmetically on the way in —

  ```bash
  declare -i v=0
  TPipe.toArray v -- printf 'abc\ndef\n'   # rc 2 now; without the check:
                                           # declare -ai v=([0]="0" [1]="0")
  ```

  Records are data, so a target that rewrites them is a malformed call. The full
  attribute matrix is [docs/TPipe.md §9](docs/TPipe.md#9-three-target-attributes-mapfile-cannot-fill).

An existing **scalar** is fine: `mapfile` converts it to an indexed array. So are
an unset name and a bare `declare -a out`.

`kk._outName` refuses `${__inst__}_data` / `_class` / `_items` only when
`__inst__` is set, i.e. when the sink is called from inside an instance member. A
top-level `TPipe.toArray h_items -- cmd` is **not** refused and would replace a
live `THashSet`'s storage — a documented boundary, not a bug.

### `toList` — duck-typed, and it counts what it OFFERED

`toList` needs one thing from `INST`: a function called `INST.Add`. That is all
it checks (`declare -F -- "$INST.Add"`), so a `TStringList`, a `TList`, a
`THashSet` and a user class all work and this unit sources none of them.

**`.Add`'s exit status is ignored.** `THashSet.Add` answers rc 1 for a duplicate
and `TStringList.Add` does the same under `dupError`; neither is a stream error.
`RESULT` is therefore the number of records **offered**, which is not always the
number the list kept:

```bash
THashSet.new h
TPipe.toList h -- printf 'a\nb\na\nb\nc\n'   # RESULT = 5 (offered)
h.Count                                       # RESULT = 3 (kept)
```

---

## 5. Stopping early

There is no "callback returns false to stop": the callback's rc is data (D2).
Stopping is an explicit call:

```bash
onLine() {
    printf '%s\n' "$1"
    if (( TPIPE_INDEX == 10 )); then TPipe.stop; fi
}
TPipe.each onLine -- find . -type f
```

* the record that asked for the stop is **fully processed**; the loop breaks
  after the callback returns;
* a stopped sink is **rc 0** — that is the consumer's success, not the producer's
  failure — and `RESULT` counts the records delivered;
* `TPipe.stop` leaves `RESULT` untouched (the callback may be mid-computation);
* **the stop is frame-local.** Each sink opens with its own `local __TPIPE_STOP`,
  and bash's **dynamic** scoping makes an assignment from any depth of callbacks
  and nested sinks land in the innermost *active* sink. So an inner sink cannot
  clear an outer sink's pending stop, an outer stop requested **before** an inner
  sink runs survives it, and a stray `TPipe.stop` outside any sink is inert. All
  four shapes are pinned in `tests/002_Stop.sh` §E; the four-line proof is
  [docs/TPipe.md §6](docs/TPipe.md#6-the-stop-flag-is-a-local-and-that-is-the-whole-nesting-design).

On the stop path the producer is **closed, then `kill -TERM`ed, then waited for**,
in that order. A SIGPIPE-honouring producer usually dies of the close
(`TPipe.lastRc` → **141**), but which of the two signals reaches it first is a
**race**: if it did not attempt a write in the window between the close and the
kill, it dies of the `TERM` (→ **143**) instead. Both are correct and neither is
worth asserting. The `TERM` is not optional: a producer that ignores SIGPIPE and
then stops writing blocks `wait` for its whole remaining life — **8.0 s measured**
for `trap '' PIPE; echo a; sleep 8; echo b`, against 15 ms with the kill. For a
short producer that had already finished, `lastRc` after a stop is simply its own
rc, so on the stop path `lastRc` means "141 / 143 / whatever the producer
managed".

`TPipe.first` takes that same stop path for free — it reads one record and ends
the stream — which is why `TPipe.first -- yes` answers in tens of milliseconds
instead of never:

```bash
TPipe.first -- yes 2>/dev/null   # RESULT='y', rc 0, lastRc 141 or 143, ~40 ms
```

`TPipe.stop` from inside a `toList` target's `.Add` works exactly as it does from
a callback: the record that asked for it is still offered, and the sink is rc 0.
`toArray`, `first` and `count` run no callback of yours, so nothing can request a
stop inside them.

---

## 6. Performance

`bash kcl/tpipe/bench.sh [N] [ND]` — deterministic sizes, no `$RANDOM`, timed
with `TStopwatch.getTimeStamp` (the shared fork-free µs clock), N = 10 000
records and ND = 2 000 dispatched calls by default. Measured **2026-09-11** on
**Windows 11 / MSYS2, with the threaded test runner idle**: The 2× gate is
calibrated for N = 10 000: at a small N (`bench.sh 2000`) the fixed per-call cost
(the process substitution, one static dispatch) dominates and the ratio reads
~2.5× — that is not a regression, re-run at the default N.

| Measurement | bash 5.2.37 | bash 5.3.9 |
|---|---|---|
| plain function call | 8.0 µs/call | 7.6 µs/call |
| kklass **static** member call | 29.1 µs/call | 26.6 µs/call |
| kklass **instance** member call (`r.onLine`) | 166.0 µs/call | 170.5 µs/call |
| **baseline** — bare `while IFS= read -r` over 10 000 records | 1831 ms (183.1 µs/rec) | 1860 ms (186.0 µs/rec) |
| `TPipe.each` + a no-op **function** | 2059 ms (205.9 µs/rec) — **1.12×** | 2108 ms (210.8 µs/rec) — **1.13×** |
| `TPipe.each` + an **instance member** (`r.onLine`) | 4172 ms (417.2 µs/rec) — **2.27×** | 4338 ms (433.8 µs/rec) — **2.33×** |
| **baseline** — bare `mapfile -t` over 10 000 records | 1663 ms (166.3 µs/rec) | 1737 ms (173.7 µs/rec) |
| `TPipe.toArray` | 1764 ms (176.4 µs/rec) — **1.06×** | 1812 ms (181.2 µs/rec) — **1.04×** |
| `TPipe.first -- yes` (infinite producer, stop path) | 41 ms, `lastRc` 141 | 42 ms, `lastRc` 141 |
| forks per record | **0** | **0** |

Reading the table:

- **The gates are the first, fourth and eighth rows** (`PLAN.md` §2.6):
  `each` + a plain function ≤ **2×** the bare loop, `toArray` ≤ **1.5×** a bare
  `mapfile`, `first` on an infinite producer ≤ **250 ms**. All three pass on both
  bashes with room to spare. `tests/005_Bench.sh` asserts the same three shapes
  with ceilings **3× looser** (6×, 4.5×, 750 ms), because ktests runs test files
  threaded with 8 workers by default and a gate set at the measured value would
  flake for reasons that have nothing to do with this unit.
- **Per call**: one fork — the producer — plus the process-substitution
  plumbing. **Per record: zero forks**, one `read`, one function call and one
  arithmetic expansion, pinned with `$BASHPID` probes in `tests/003_Sinks.sh` §K
  and `tests/005_Bench.sh` §C.
- **The reader costs almost nothing.** 183 µs/rec of the baseline is what a bare
  `read` from a pipe costs on this platform; TPipe adds ~23 µs on top of it, the
  price of one function call and one `(( ))`.
- **`toArray` is the cheap sink**: `mapfile` reads the whole stream in one
  builtin call, so there is no per-record cost at all and the ratio is within
  measurement noise of 1. `-c` adds one extra pass over the finished array (still
  fork-free). `toList` costs whatever `INST.Add` costs — a full kklass instance
  dispatch per record.
- **An instance-member callback is a different order of magnitude, and it is
  kklass's price, not TPipe's.** 166/170 µs per instance dispatch against 8.0/7.6
  µs for a plain function is the 20× that turns the 1.12× row into the 2.27× row.
  Callers with 10⁵-record streams should reach for `TPipe.toArray` + a plain
  loop, or for a plain-function callback that forwards to the object only when it
  must:

  ```bash
  onLine() { [[ "$1" == *ERROR* ]] && r.onError "$1"; return 0; }
  TPipe.each onLine -- journalctl -f      # one dispatch per HIT, not per record
  ```

---

## 7. Traps and limits

* **A record containing a NUL byte cannot be delivered.** No bash variable can
  hold one (`a\0b` arrives as `ab`) — the same carve-out `tfile` documents. `-0`
  is about the *delimiter*, not about NULs inside a record.
* **TPipe never times a producer out.** `-- cat`, `-- sleep 30`, `-- ssh host
  tail -f` block in `read` until the producer writes or exits. `timeout(1)` in
  the argv (`-- timeout 5 cmd`) is the tool; it exists on both targets and kills
  the whole process-substitution tree, which the engine's own `kill -TERM`
  cannot — a process substitution is not a process-group leader.
* **The producer's stderr passes through untouched.** A caller who wants it
  captured redirects it inside a wrapper function named as `CMD`. On the stop
  path a producer routinely prints `write error: Broken pipe`; that is the
  producer's output, not TPipe's — and `TPipe.first` is always on the stop path,
  so `TPipe.first -- yes 2>/dev/null` is the idiomatic spelling.
* **stdin is shared, not consumed whole.** `TPipe.first` in the stdin form reads
  exactly one record and leaves the rest of stdin for the caller; the `--` form's
  producer inherits the caller's stdin untouched (§2).
* **Single producer.** `-- a -- b` is not a pipeline; a real `|` under `lastpipe`
  already composes any number of stages.
* **`__TPIPE_QUIET` — the composing caller's opt-out from the `$( )` echo.**
  `tpipe._ret` prints `RESULT` under any `BASH_SUBSHELL > 0`, which is right for
  a caller that *is* the answer (`n=$(TPipe.count -- cmd)`) and wrong for one
  that *composes*: a member of your own class that runs a sink and then answers
  through its own `kk._return` gets the value printed **twice** (measured while
  `tutil` P1 was written: `$(u.count)` read back as `22`). Such a caller
  declares the flag as a `local` of its own frame, and bash's **dynamic**
  scoping carries it into the sink and ends it with the frame — the same
  mechanism `local __TPIPE_STOP` uses:

  ```bash
  TMy.count() {                       # a kklass member that wraps a sink
      local __TPIPE_QUIET=1
      TPipe.count -- "${argv[@]}" || :
      kk._return "$RESULT"            # ONE print under $( ), not two
  }
  ```

  It silences `tpipe._ret` and **nothing else**: a callback's own stdout, a
  `toList` target's `.Add` output and the producer's stderr all pass through
  untouched, and `RESULT` is set exactly as before, so a direct call is
  unaffected either way. kklass's `__kk_return_silent` cannot be borrowed for
  this — the thin static dispatcher sets it to `1` for every static body, so a
  static member could never tell the two states apart. Sourcing the unit
  declares `__TPIPE_QUIET=0` globally, so a read under `set -u` outside any sink
  is safe. **The one thing to know:** dynamic scoping means a *callback* invoked
  by that sink also sees the `1`, so a callback that itself does
  `x=$(TPipe.count -- …)` must declare `local __TPIPE_QUIET=0` first. Pinned in
  `tests/004_Contract.sh` §6. `each` needs none of this: by D6 final Q7 it never
  prints at all (§3).
* **`KK_SUBSHELL_OK` is a kcl-wide name, not a tpipe one.** It lives in the `KK_`
  space on purpose (D6 final Q4), is read only on the warning path, and is never
  written by this unit. A caller sets it per call (`KK_SUBSHELL_OK=1 sink …`) or
  per block (`local KK_SUBSHELL_OK=1`); anything other than the exact value `1`
  leaves the warning on.
* **Reserved names.** `__tpi_*`, `__TPIPE_*` and `TPIPE_INDEX` belong to this
  unit, on top of kklass's `this __inst__ __class__ RESULT REPLY IFS state
  __kk_*`. Never bind an output array to any of them — `TPipe.toArray` refuses
  every one of them with rc 2. The `__tpi_*` locals are visible to your callback
  through bash's dynamic scoping; treat them as read-only and do not declare your
  own.
* **The `-c` pattern lives in `__TPIPE_CR`, never inline.** `build` re-creates
  every member body from `declare -f` through `eval`, and a literal `$'\r'`
  written inside a body does **not** survive that round trip: `declare -f` prints
  it as a raw carriage return inside quotes and the re-parse drops it, leaving
  `${x%''}` — a pattern that matches the empty string, strips nothing and says
  nothing (measured on 5.2.37 and 5.3.9; P0 shipped `-c` as a silent no-op this
  way and P1 caught it). **This is a kklass-wide trap**, not a tpipe one: any
  future member body that needs a CR — or any other character bash's parser eats
  — must take it from a variable built at load time. Plain helper functions,
  which `build` does not touch, are unaffected. The proof is
  [docs/TPipe.md §8](docs/TPipe.md#8-an-inline-r-does-not-survive-build).
* **`declare -F` accepts `--`.** Bare, it reads the argument as the
  end-of-options marker, lists every function and reports success — so the
  callback validator is `declare -F -- "$cb"`, and `--` on its own is refused as
  an operand before that.
* **The delimiter is a value, never an expansion.** `read -r ${d:+-d ''}` is
  split by the **caller's** `IFS`, and `IFS=':'` silently turns the NUL delimiter
  into a space (one record `ab` instead of two). The unit spells
  `read -r -d "$__tpi_d"`.

---

## 8. Tests

```bash
bash kcl/tpipe/tests/tests.sh                  # 5.2.37
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe kcl/tpipe/tests/tests.sh
```

**190 checks**, green on bash 5.2.37 and on 5.3.9, in the default threaded mode
and under `--mode single`. Every case is indexed in
[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md).

| File | Cases | What it pins |
|---|---|---|
| `001_Each.sh` | 44 | the producer's real rc through `wait` (F3), delivery and the unterminated/empty tail (F10), records as data (the exotic matrix), `TPIPE_INDEX` (F13), the callback matrix — plain / instance / static, from top level and from inside another member (F9), every rc 2 path, the stdin form in a pipe RHS delivering while the parent's object stays untouched and the stdin warning template verbatim — printed with the debug switch off, silenced by `-s` and by `quiet`, absent for a plain-function callback (F1, D6 final), `lastpipe` (F2), the two README forms, and Q7: `each` never prints |
| `002_Stop.sh` | 13 | the close-kill-wait path on an infinite producer (F4) and on a SIGPIPE-ignoring one (F5), both through `each` + `stop` and through `first`, `$!` clobbered by a callback (F6), the frame-local stop in all four shapes (F12), `stop` leaves `RESULT` alone, the `lastRc` sentinels |
| `003_Sinks.sh` | 68 | `toArray`/`toList`/`first`/`count` against their bare-bash oracles (`mapfile`, a `while read` loop, `head -n1`, `wc -l`), the exotic matrix byte-exact through `toArray`, a kklass class and a real `TStringList` (64 KiB record included), the `-0` NUL path over `find -print0` on names with a space and a newline (F7), `-c` stripping exactly one CR through every sink, the delimiter surviving `IFS=':'` (F11), the assoc/integer/readonly refusal (F15), rc 2 paths running nothing (F14), stdin pass-through (F16), the rc 1 + non-empty RESULT deviation, a rejecting `.Add`, nesting, and the zero-fork probes |
| `004_Contract.sh` | 59 | `bash -n` + the open-quote grep, every sink in both forms under `set -eu` (including the stop path, a rejecting `.Add`, a predicate callback and a producer exiting 4 — the child must die of the member's rc 1, not the producer's 4), exactly one `kk.debug` line per rc 2 path with the switch on and none with it off, §3 the whole D6-final matrix (both templates × `each`/`toArray`/`toList` byte-exact, `first`/`count` silent, a plain-function and a static-member callback silent, `-s` / a `KK_SUBSHELL_OK=1` prefix / `local KK_SUBSHELL_OK=1` / `VERBOSE_KKLASS=quiet` each silent, the line printed with the debug switch off, an rc 2 path in a subshell printing its `Error:` line and never a `Warning:`, and nothing at all at `BASH_SUBSHELL` 0), §4 the Q7 pins (`$( )` and a pipe carry only the callback's bytes, a direct call sets `RESULT`, rc 2 leaves it empty), and §6 `__TPIPE_QUIET`: the flag silences `tpipe._ret` only (a callback's and a `.Add`'s stdout still flow), the default is unchanged, a direct call is unaffected either way, and the load-time global is readable under `set -u` |
| `005_Bench.sh` | 6 | the `PLAN.md` §2.6 gates as assertions with ceilings 3× looser than the measured values (the runner is threaded ×8), the `first`-on-`yes` latency in a child under `timeout`, and zero forks per record for every sink |

The exact numbers come from `bench.sh`, run by hand — §6.
