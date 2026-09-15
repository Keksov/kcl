# TPipe — the design record

> **There is no upstream reference for this unit.** Every other `docs/*.md` page
> in kcl is a scrape of the FPC/Delphi class being ported, kept so the port can
> be checked against it. `TPipe` has no such page to scrape: it is a **kcl
> addition**, like `tfile.readAllTextVar` and `THashSet.AddRangeFromArray`, born
> from a bash fact rather than from a Pascal class. So this page is the material
> the port was checked against — the measurements the design rests on, each as a
> runnable script with the output it produced on both target bashes. The
> normative API and contract is **[../README.md](../README.md)**; where this page
> and the README disagree, the README wins.
>
> * **Ported:** nothing. No FPC unit, no Delphi unit, no RTL analogue. The
>   nearest Pascal relatives are `TProcess` + `TStream` (start a program, read
>   its output in your own process), which is the *shape* of the problem but
>   shares no API: `TPipe` has no handle, no stream object and no lifecycle —
>   one call runs one producer to EOF (or to `TPipe.stop`).
> * **Roadmap:** `tutil` (the wrapper base) and `TGrep` (the first wrapper),
>   which delegate their sinks to this unit and add the README's *form 3*
>   (`g.each r.onLine`). Nothing is planned inside `tpipe` itself; the surface of
>   §1.3 of [../PLAN.md](../PLAN.md) is final and a change to it needs an owner
>   decision.
> * **Wontfix:** nine items, listed with their reasons in [§10](#10-wontfix)
>   below (`PLAN.md` §1.4).
> * **Return contract:** a direct call prints nothing and leaves the value in
>   `RESULT`; inside `$( )` the value prints exactly once. `each`, `toArray`,
>   `toList` and `count` answer the record count with rc 0, or rc 1 **with the
>   count kept** when the producer exited non-zero (the named deviation from
>   kcl `README.md` §1.2); `first` answers the record itself, rc 1 only when
>   there was none. A malformed **call** is rc 2, `RESULT=''`, and runs nothing.

**How to read the measurements.** Every section below is a script that can be
pasted into a file and run. Each was run on **bash 5.2.37 (MSYS2 `bash`)** and on
**bash 5.3.9 (`C:/bin/msys64/usr/bin/bash.exe`)**, sequentially, on Windows 11 /
MSYS2. Where the output was byte-identical on the two — which is every section
but §4, where the numbers are timings — it is shown once and said so. The probes
were first run on **2026-09-10** during the design (`PLAN.md` §1.1) and by the
critic (`PLAN.md` §8); the outputs printed here are the **2026-09-11 re-runs at
P2**, against the unit as shipped.

---

## 1. The problem: the right-hand side of `|` is a subshell

This is the whole reason the unit exists. An object that counts lines keeps its
count when it is fed by a process substitution or under `lastpipe`, and loses it
in an ordinary pipe — silently, with no error anywhere.

```bash
#!/bin/bash
source /c/projects/kkbot/kbool/kklass/kklass_pascal.sh

class TCounter
    public
        var         N
        constructor Create
        proc        onLine
end
TCounter.Create() { N=0; return 0; }
TCounter.onLine() { local l; while IFS= read -r l; do N=$(( N + 1 )); done; return 0; }
build TCounter

TCounter.new c; printf 'a\nb\nc\n' | c.onLine;       printf 'pipe RHS        N='; c.N
TCounter.new d; d.onLine < <( printf 'a\nb\nc\n' );  printf '< <(producer)   N='; d.N
shopt -s lastpipe
TCounter.new e; printf 'a\nb\nc\n' | e.onLine;       printf 'pipe + lastpipe N='; e.N
```

Identical on 5.2.37 and 5.3.9:

```
pipe RHS        N=0
< <(producer)   N=3
pipe + lastpipe N=3
```

Three lines went in and the object saw all three in every case. In the first
case the *object that saw them* was a copy in a subshell that then exited. There
is no diagnostic, no non-zero status and no partial state: the count is simply 0.

`TPipe` gives the second row a name. `TPipe.each c.onLine -- producer` reads the
producer through `exec {fd}< <(...)` in the **calling** shell, so the callback
mutates the real object.

## 2. `BASH_SUBSHELL` is the discriminator

Decision **D1** (refuse the stdin form inside a subshell) needs a test that is
true exactly when the caller's mutations are about to be thrown away.
`BASH_SUBSHELL` is that test, and — the part that had to be measured — the two
extra function frames kklass's thin static dispatcher adds do not disturb it.

```bash
#!/bin/bash
source /c/projects/kkbot/kbool/kklass/kklass_pascal.sh

class TProbe
    public
        static proc where
end
TProbe.where() { printf '%-28s BASH_SUBSHELL=%s\n' "$1" "$BASH_SUBSHELL"; }
build TProbe

TProbe.where "top level"
echo x | TProbe.where "pipe RHS"
v=$( TProbe.where "inside \$( )" ); printf '%s\n' "$v"
cat < <( TProbe.where "inside <( ) body" )
( TProbe.where "inside ( )" )
shopt -s lastpipe
echo x | TProbe.where "pipe RHS + lastpipe"
{ printf 'a\n'; exit 3; } | TProbe.where "a FAILING producer"
printf 'PIPESTATUS of that pipeline: (%s)\n' "${PIPESTATUS[*]}"
```

Identical on 5.2.37 and 5.3.9:

```
top level                    BASH_SUBSHELL=0
pipe RHS                     BASH_SUBSHELL=1
inside $( )                  BASH_SUBSHELL=1
inside <( ) body             BASH_SUBSHELL=1
inside ( )                   BASH_SUBSHELL=1
pipe RHS + lastpipe          BASH_SUBSHELL=0
a FAILING producer           BASH_SUBSHELL=0
PIPESTATUS of that pipeline: (3 0)
```

Four consequences the unit is built on:

* the refusal of D1 fires on the pipe RHS, on `$( )` and on `( )`, and **not** on
  a legitimate `TPipe.each cb < file` at top level;
* `lastpipe` really does put a kklass **static member** in the calling shell, so
  the README's *form 1* works;
* `PIPESTATUS[0]` under `lastpipe` is the producer's own status — which is why
  `TPipe.lastRc` answers `-1` for the stdin form instead of inventing a number:
  the caller has a correct one right there;
* a warning, not a refusal, is the right answer for the `--` form in a subshell
  (**D6**): the records *are* delivered there, only the mutations are lost, and
  the `$( )` is the caller's own explicit choice.

## 3. The engine: `exec {fd}< <(cmd)`, a captured pid, and a guarded `wait`

The producer must be startable without a pipe, its **real** exit status must be
recoverable, and the whole thing must survive a callback that starts jobs of its
own.

```bash
#!/bin/bash
run() {                                  # run LABEL -- CMD...
    local label="$1"; shift 2
    local fd pid rc=0 n=0 line
    exec {fd}< <( "$@" )
    pid=$!
    while IFS= read -r -d $'\n' -u "$fd" line || [[ -n "$line" ]]; do n=$(( n + 1 )); done
    exec {fd}<&-
    wait "$pid" || rc=$?
    printf '%-34s records=%s  wait rc=%s\n' "$label" "$n" "$rc"
}
pfunc6()  { printf 'a\n'; return 6; }

run "external producer, exit 4"  -- bash -c 'printf "a\nb\n"; exit 4'
run "shell FUNCTION producer, 6" -- pfunc6
run "a command that is not there" -- tpipe_no_such_command_at_all

exec {fd}< <( bash -c 'printf "a\n"; exit 9' )
pid=$!
( : ) &                                  # this overwrites $!
wait $! 2>/dev/null || :
cat <&"$fd" >/dev/null
exec {fd}<&-
rc=0;  wait "$pid" || rc=$?
rc2=0; wait "$pid" 2>/dev/null || rc2=$?
printf '%-34s first wait rc=%s, second wait rc=%s\n' "captured pid after a \$! clobber" "$rc" "$rc2"
```

Identical on 5.2.37 and 5.3.9 (the `command not found` line is the producer's own
stderr passing through, §10 item 7):

```
external producer, exit 4          records=2  wait rc=4
shell FUNCTION producer, 6         records=1  wait rc=6
p3_fd_wait.sh: line 6: tpipe_no_such_command_at_all: command not found
a command that is not there        records=0  wait rc=127
captured pid after a $! clobber    first wait rc=9, second wait rc=9
```

So: a **shell function** is as good a producer as an executable (which is what
lets `-- TGrep.search …` work with no plumbing); a missing command reports `127`
through `wait` with no pre-check of our own; `$!` captured immediately is stable
even after a callback starts a job (**F6**); and `wait` on the same pid twice
answers the same thing, which is why `tpipe._close` can be called on any path.

Two rules come out of this section and are enforced in the unit:

* **`wait` is guarded, always**: `__TPIPE_RC=0; wait "$pid" || __TPIPE_RC=$?`.
  A bare `wait` on a producer that exited 4 aborts a `set -e` caller before
  `RESULT` is ever assigned. `tests/004_Contract.sh` tells the two apart by the
  child's own exit status: 1 (the member's) and not 4 (the producer's).
* **the fd is closed before the `wait`, never after** — see §4.

## 4. Stopping a producer: close, then `kill -TERM`, then wait

`TPipe.stop` and `TPipe.first` end the stream while the producer is still
running. Closing the read end is enough for a producer that honours SIGPIPE. It
is **not** enough for one that ignores it and then stops writing: `wait` then
blocks for the producer's whole remaining life.

```bash
#!/bin/bash
now() { local t=$EPOCHREALTIME; US=$(( ${t%[.,]*} * 1000000 + 10#${t##*[.,]} )); }

stop_after_one() {        # stop_after_one kill|nokill -- CMD...
    local withkill="$1"; shift 2
    local name="$1" fd pid rc=0 line t0 t1
    now; t0=$US
    exec {fd}< <( "$@" 2>/dev/null )
    pid=$!
    IFS= read -r -u "$fd" line || :
    exec {fd}<&-
    if [[ "$withkill" == "kill" ]]; then
        kill -TERM "$pid" 2>/dev/null || :
    fi
    wait "$pid" || rc=$?
    now; t1=$US
    printf '%-18s %-7s first=%-3s wait rc=%-4s elapsed=%s ms\n' \
        "$name" "$withkill" "$line" "$rc" $(( (t1 - t0) / 1000 ))
}

sigpipe_sleeper() { trap '' PIPE; printf 'a\n'; sleep 8; printf 'b\n'; }

stop_after_one kill   -- yes
stop_after_one nokill -- yes
stop_after_one kill   -- sigpipe_sleeper
stop_after_one nokill -- sigpipe_sleeper

exec {fd}< <( yes 2>/dev/null )
pid=$!
krc=0; kill -- -"$pid" 2>/dev/null || krc=$?
printf '%-26s kill -- -PID rc=%s (1 = no such process group)\n' "procsub as group leader" "$krc"
exec {fd}<&-; kill -TERM "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :
```

bash 5.2.37:

```
yes                kill    first=y   wait rc=141  elapsed=34 ms
yes                nokill  first=y   wait rc=141  elapsed=26 ms
sigpipe_sleeper    kill    first=a   wait rc=143  elapsed=15 ms
sigpipe_sleeper    nokill  first=a   wait rc=1    elapsed=8047 ms
procsub as group leader    kill -- -PID rc=1 (1 = no such process group)
```

bash 5.3.9:

```
yes                kill    first=y   wait rc=141  elapsed=30 ms
yes                nokill  first=y   wait rc=141  elapsed=26 ms
sigpipe_sleeper    kill    first=a   wait rc=143  elapsed=15 ms
sigpipe_sleeper    nokill  first=a   wait rc=1    elapsed=8059 ms
procsub as group leader    kill -- -PID rc=1 (1 = no such process group)
```

Row by row:

* **`yes`** dies of SIGPIPE on its next write as soon as the fd is closed —
  `141`, in tens of milliseconds, with or without the kill.
* **the SIGPIPE-ignoring sleeper** without the kill blocks `wait` for **8.0 s**,
  its full `sleep 8`, and then answers rc 1 (its own status) — the stream was
  over in 15 ms and the caller waited eight seconds for nothing. This was a
  critic BLOCKER.
* the same producer **with** the `kill -TERM` is gone in 15 ms with `143`.
* `kill -- -"$pid"` answers rc 1: a process substitution is **not** a
  process-group leader, so the group form cannot be used to reap its children.
  Killing the procsub itself is what the engine does; `timeout(1)` inside the
  argv is the tool for a producer whose own children must go too (§10 item 6).

Which signal wins on `yes` is a **race** — the close and the kill are two
statements apart, and under load (the 5.3.9 master sweep at P0) the TERM landed
before `yes` attempted its next write. Both 141 and 143 are correct and the tests
accept either for a SIGPIPE-honouring producer; **F5** stays strict at 143,
because a producer that ignores SIGPIPE can only die of the TERM.

And this is why the member's own rc is **0** on the stop path even though `wait`
reported a signal: the consumer ended the stream on purpose. The producer's
141/143 stays visible through `TPipe.lastRc`.

## 5. The record delimiter must be passed as a value

The first draft spelled the reader's header `read -r ${d:+-d ''}`. That is an
option word built by **expansion**, so it is subject to word splitting on the
**caller's** `IFS` — which the `IFS=` prefix of the `read` does not affect,
because that prefix applies to the command's own environment, not to the
expansion of its arguments.

```bash
#!/bin/bash
count_expanded() {              # the BROKEN form
    local nul=1 fd n=0 line
    exec {fd}< <( printf 'a\0b\0' )
    while IFS= read -r ${nul:+-d ''} -u "$fd" line || [[ -n "$line" ]]; do
        n=$(( n + 1 ))
    done
    exec {fd}<&-
    printf '%s' "$n"
}
count_value() {                 # the form the unit uses
    local d='' fd n=0 line
    exec {fd}< <( printf 'a\0b\0' )
    while IFS= read -r -d "$d" -u "$fd" line || [[ -n "$line" ]]; do
        n=$(( n + 1 ))
    done
    exec {fd}<&-
    printf '%s' "$n"
}
for mode in default colon; do
    if [[ "$mode" == colon ]]; then IFS=':'; else unset IFS; fi
    printf 'IFS=%-8s  ${nul:+-d ..} -> %s record(s)   -d "$d" -> %s record(s)  (want 2)\n' \
        "$mode" "$(count_expanded)" "$(count_value)"
done
unset IFS
```

Identical on 5.2.37 and 5.3.9:

```
IFS=default   ${nul:+-d ..} -> 2 record(s)   -d "$d" -> 2 record(s)  (want 2)
IFS=colon     ${nul:+-d ..} -> 1 record(s)   -d "$d" -> 2 record(s)  (want 2)
```

With `IFS=':'` the string `-d ` is not split at all, `read` receives it as one
word, and the delimiter silently becomes a **space**: `a\0b\0` arrives as the
single record `ab`. Nothing is reported. The unit therefore keeps the delimiter
in `__tpi_d` and writes `read -r -d "$__tpi_d"`; `mapfile -t -d "$__tpi_d"` in
`toArray` does the same, and `-d $'\n'` is identical to `mapfile`'s default.
Pinned as **F11** in `tests/003_Sinks.sh` §F.

## 6. The stop flag is a `local`, and that is the whole nesting design

Bash scopes `local` **dynamically**: a name declared in a caller's frame is
visible to everything it calls, and an assignment from any depth lands in the
innermost frame that declared it. A stop flag declared `local` by every sink
therefore gets all four nested semantics with no bookkeeping at all.

```bash
#!/bin/bash
declare -g FLAG=0            # the process-wide slot a STRAY stop would write
declare -g RES=''            # stands in for RESULT

stop() { FLAG=1; }           # the same one line as TPipe.stop

sink() {                     # the same `local FLAG=0` every sink opens with
    local FLAG=0 cb="$1" n=0 i
    for i in a b c d; do
        n=$(( n + 1 ))
        "$cb" "$i"
        if (( FLAG )); then break; fi
    done
    RES="$n"
}

inner_plain() { :; }
inner_stop()  { stop; }
outer_a() { if [[ "$1" == b ]]; then stop; sink inner_plain; INNER="$RES"; fi; }
outer_b() { if [[ "$1" == a ]]; then sink inner_stop;        INNER="$RES"; fi; }

INNER=''; sink outer_a
printf 'outer stop BEFORE an inner sink : outer=%s inner=%s (want 2 / 4)\n' "$RES" "$INNER"
INNER=''; sink outer_b
printf 'stop inside the INNER callback  : outer=%s inner=%s (want 4 / 1)\n' "$RES" "$INNER"
stop; sink inner_plain
printf 'a STRAY stop                    : global FLAG=%s, the next sink still runs %s records\n' \
    "$FLAG" "$RES"
```

Identical on 5.2.37 and 5.3.9:

```
outer stop BEFORE an inner sink : outer=2 inner=4 (want 2 / 4)
stop inside the INNER callback  : outer=4 inner=1 (want 4 / 1)
a STRAY stop                    : global FLAG=1, the next sink still runs 4 records
```

The first draft used one **global** flag cleared on sink exit, and lost row 1:
the outer stop requested *before* the inner sink ran was wiped by the inner
sink's own cleanup, so the outer delivered 4 records instead of 2 (critic MAJOR
#3). With a frame-local slot there is nothing to clear — frames unwind on their
own. The process-wide `__TPIPE_STOP=0` declared at load exists only so that a
**stray** `TPipe.stop`, called outside any sink, has somewhere to write and never
trips `set -u`; no sink ever reads it. Pinned as **F12** in `tests/002_Stop.sh` §E.

`(( __TPIPE_STOP ))` as a bare statement returns 1 when the flag is 0, which
would abort a `set -e` caller — hence `if (( __TPIPE_STOP )); then break; fi` and
never the bare form.

## 7. `declare -F` accepts `--` as a callback name

The callback validator is one line, and without the `--` it has a hole.

```bash
#!/bin/bash
probe() {
    local rc1=0 rc2=0 out
    out="$(declare -F "$1" 2>/dev/null)" || rc1=$?
    declare -F -- "$1" >/dev/null 2>&1   || rc2=$?
    printf 'cb=%-20s  declare -F CB -> rc %s, %s name(s) listed    declare -F -- CB -> rc %s\n' \
        "'$1'" "$rc1" "$( [[ -z "$out" ]] && echo 0 || grep -c . <<< "$out" )" "$rc2"
}
myfunc() { :; }
probe myfunc
probe no_such_function
probe --
```

Identical on 5.2.37 and 5.3.9:

```
cb='myfunc'              declare -F CB -> rc 0, 1 name(s) listed    declare -F -- CB -> rc 0
cb='no_such_function'    declare -F CB -> rc 1, 0 name(s) listed    declare -F -- CB -> rc 1
cb='--'                  declare -F CB -> rc 0, 2 name(s) listed    declare -F -- CB -> rc 1
```

Bare, `declare -F --` reads its argument as the end-of-options marker, lists
**every** function in the shell and reports success — so `TPipe.each -- …` would
have been accepted with `--` as the callback and then failed at the first record
with a bash "command not found". `declare -F -- "$cb"` closes it (a P0 worker
finding, `PLAN.md` §6), and `tpipe._open` additionally refuses an operand equal
to `--` before the validator is ever reached, so the error the caller gets is
"missing argument before `--`" and not something about functions.

## 8. An inline `$'\r'` does not survive `build`

kklass's `build` extracts every declared member's body with `declare -f` and
re-creates it through `eval`. A `$'…'` string holding a **control character** is
printed by `declare -f` as that raw character inside ordinary quotes, and the
re-parse drops it. P0 shipped `-c` (strip one trailing CR) this way and it
stripped nothing — silently. P1 caught it.

```bash
#!/bin/bash
strip_inline() { printf '%s' "${1%$'\r'}"; }        # what P0 shipped
printf -v CR '\r'
strip_var()    { printf '%s' "${1%"$CR"}"; }        # what P1 ships

echo 'declare -f strip_inline | cat -v   (^M is a RAW carriage return):'
declare -f strip_inline | cat -v | sed 's/^/    /'

eval "$( declare -f strip_inline | sed 's/^strip_inline/strip_rebuilt/' )"
echo 'declare -f strip_rebuilt | cat -v  (after the eval round trip):'
declare -f strip_rebuilt | cat -v | sed 's/^/    /'

x=$'data\r'
printf 'inline   strip: [%s]\n' "$(strip_inline  "$x" | cat -v)"
printf 'rebuilt  strip: [%s]   <- the CR is BACK; the pattern became empty\n' "$(strip_rebuilt "$x" | cat -v)"
printf 'from a variable: [%s]\n' "$(strip_var     "$x" | cat -v)"
printf 'exactly ONE CR : [%s]  (input data\\r\\r)\n' "$(strip_var $'data\r\r' | cat -v)"
```

Identical on 5.2.37 and 5.3.9:

```
declare -f strip_inline | cat -v   (^M is a RAW carriage return):
    strip_inline ()
    {
        printf '%s' "${1%'^M'}"
    }
declare -f strip_rebuilt | cat -v  (after the eval round trip):
    strip_rebuilt ()
    {
        printf '%s' "${1%''}"
    }
inline   strip: [data]
rebuilt  strip: [data^M]   <- the CR is BACK; the pattern became empty
from a variable: [data]
exactly ONE CR : [data]  (input data\r\r)
```

`${1%'^M'}` became `${1%''}` — a suffix pattern that matches the empty string, so
the strip is a no-op that reports nothing. The fix is a load-time
`printf -v __TPIPE_CR '\r'` and a body that spells `${__tpi_line%"$__TPIPE_CR"}`:
a **value** is never re-parsed. The double quotes around the expansion keep it a
literal match rather than a glob, and it strips exactly one CR (`x\r\r` → `x\r`).
`tr` was rejected: a fork per call, and it would eat CRs inside the record too.

**This is a kklass-wide trap, not a tpipe one.** Any member body carrying a
`$'…'` with a control character has the same hole, and plain helper functions
(which `build` does not touch) do not. Recorded in `PLAN.md` §6;
`tests/003_Sinks.sh` §F asserts that the shipped `-c` really strips, in every
sink, and that the pattern survived the round trip.

## 9. Three target attributes `mapfile` cannot fill

`toArray` fills the caller's array with `mapfile`. Three kinds of target have to
be refused **before** the producer starts, two because bash prints a diagnostic
(a kcl unit must never emit one) and one because it corrupts the records in
silence.

```bash
#!/bin/bash
# NB: the mapfile runs in THIS shell — inside a `$( )` the fill would be thrown
# away and every case would look harmless.
ERR="${TMPDIR:-/tmp}/p9.err"
try() {                     # try LABEL NAME
    local rc
    : > "$ERR"
    mapfile -t "$2" < <( printf 'abc\ndef\n' ) 2>"$ERR"; rc=$?
    printf '%-20s rc=%s  stderr=%-42s  %s\n' \
        "$1" "$rc" "'$(sed 's/^[^:]*: line [0-9]*: //' "$ERR" | tr '\n' ' ')'" \
        "$(declare -p "$2" 2>&1)"
}
declare -A ASSOC=()
declare -i INT=0
declare -a RO=(); readonly RO
declare ROS=x;    readonly ROS
declare -a PLAIN=()
SCALAR=hello
try "associative (-A)" ASSOC
try "integer (-i)"     INT
try "readonly array"   RO
try "readonly scalar"  ROS
try "plain array"      PLAIN
try "existing scalar"  SCALAR
try "unset name"       NEVER_SET
rm -f "$ERR"
```

Identical on 5.2.37 and 5.3.9:

```
associative (-A)     rc=1  stderr='mapfile: ASSOC: not an indexed array '     declare -A ASSOC=()
integer (-i)         rc=0  stderr=''                                          declare -ai INT=([0]="0" [1]="0")
readonly array       rc=1  stderr='RO: readonly variable '                    declare -ar RO=()
readonly scalar      rc=1  stderr='ROS: readonly variable '                   declare -r ROS="x"
plain array          rc=0  stderr=''                                          declare -a PLAIN=([0]="abc" [1]="def")
existing scalar      rc=0  stderr=''                                          declare -a SCALAR=([0]="abc" [1]="def")
unset name           rc=0  stderr=''                                          declare -a NEVER_SET=([0]="abc" [1]="def")
```

The `-i` row is the interesting one and was **not** in the critic's list: the
call *succeeds*, silently, and every record is evaluated **arithmetically** on
the way in — `abc` and `def` both became `0`. Records are data; a target that
rewrites them is a malformed call, so `tpipe._isBadTarget` refuses `A`, `i` and
`r` alike with rc 2 and no stderr (a P1 worker finding). The last three rows are
the accepted shapes: a plain array, an existing **scalar** (converted) and an
unset name all work.

`tpipe._isBadTarget` reads the attribute string through a nameref, and
`${ref@a}` aborts under `set -u` when the target has no value yet — which
`declare -a out=()`, the normal way to prepare a receiving array, is. It
therefore uses `local -` + `set +u`, the same shape as `TSet._isAssoc`
(`thashset.sh:242`), so the option change costs no fork and cannot leak to the
caller. Pinned as **F15** in `tests/003_Sinks.sh` §B.

## 10. Wontfix

Nine items, from `PLAN.md` §1.4. None of them is a missing feature waiting for a
phase; each is a decision.

| # | Not in scope | Why |
|---|---|---|
| 1 | a comma / string command form — `TPipe.call "grep x", cb` | a comma is not a separator in bash, and a command-as-string needs `eval`. The argv form (`-- CMD ARG...`) is the whole point |
| 2 | a literal `'\|'` token — `TPipe.run cmd '\|' cb` | an unquoted `\|` degrades to the real pipe, silently, which is the exact trap this unit exists to remove |
| 3 | setting `shopt -s lastpipe` from the unit | a global shell option changed behind the caller's back — and inert while job control is on, so it would not even work in an interactive shell. Detected and refused instead (D1) |
| 4 | multi-stage pipelines in the `--` form (`-- a -- b`) | a real `\|` under `lastpipe` already composes any number of stages; the `--` form is single-producer by design |
| 5 | a callback-per-field / awk-style splitter | that is `tstringhelper.split` on the record, inside the callback |
| 6 | timeouts on the producer | `timeout(1)` in the argv (`-- timeout 5 cmd`) is the tool, it exists on both targets, and it kills the whole process-substitution tree — which §4 shows the engine itself cannot do. `TPipe.first -- sleep 30` blocks in `read` until the producer writes or exits, and that is the documented behaviour |
| 7 | stderr capture | the producer's stderr passes through untouched (unix). A caller who wants it redirects it inside a wrapper function named as `CMD` |
| 8 | records containing NUL | a bash **language** limit: no variable can hold a NUL (`a\0b` arrives as `ab`). Documented next to tfile's identical carve-out. `-0` is about the *delimiter*, not about NULs inside a record |
| 9 | a `-0`-aware `first`/`count` that also splits on `\n` | one delimiter per call |

## 11. The critic pass, and where each finding landed

An Opus critic reviewed the first draft of `PLAN.md` against the live tree on
**2026-09-10** with 15 probe scripts on both bashes: 2 BLOCKER, 8 MAJOR, 8 MINOR,
5 NIT. Every one was folded into the plan before any code was written, which is
why the design sections above read as settled. The table is `PLAN.md` §8; this is
where each finding ended up in the shipped unit.

| # | sev | finding | landed in |
|---|---|---|---|
| 1 | BLOCKER | `${d:+-d ''}` is split by the caller's `IFS` | §5 above; `read -d "$__tpi_d"`; F11 |
| 2 | BLOCKER | a SIGPIPE-ignoring producer that stops writing blocks `wait` for its whole life | §4 above; close → `kill -TERM` → guarded `wait`; F5 |
| 3 | MAJOR | a global stop flag reset on exit loses an outer stop | §6 above; `local __TPIPE_STOP` per sink frame; F12 |
| 4 | MAJOR | the `--` form under `$( )` also loses instance-callback state | **D6**: allowed with one `kk.debug` warning; README §3 |
| 5 | MAJOR | rc 1 with a non-empty `RESULT` contradicts kcl §1.2 | the **named deviation**, README §4 and the kcl README §2 row |
| 6 | MAJOR | the perf gates were measured against the wrong callback | gates are the **plain-function** path; the instance-member number is published separately (`bench.sh` §a/§c, README §6) |
| 7 | MAJOR | ktests runs files threaded ×8 by default, so a 50 ms gate flakes | 250 ms in the plan, and `tests/005_Bench.sh` asserts ceilings 3× looser still |
| 8 | MAJOR | `mapfile` into an assoc/readonly target prints a bash diagnostic | §9 above; `tpipe._isBadTarget`; F15 |
| 9 | MAJOR | the producer inherits the caller's stdin, so tests behave differently per runner mode | documented (README §2); every test sets its own stdin; F16 |
| 10 | MAJOR | a bare `wait` aborts a `set -e` caller | §3 above; `tests/004_Contract.sh` §1 |
| 11 | MINOR | `lastRc = 0` for the stdin form lies | `-1`, with `${PIPESTATUS[0]}` named as the replacement (§2) |
| 12 | MINOR | NUL inside a record is dropped by `read` | §10 item 8 |
| 13 | MINOR | producers that never write block `first`/`each` | §10 item 6 |
| 14 | MINOR | the cited `THashSet.ForEach` answers rc 1, not 2 | the citation in `tpipe._isFunc` is `THashSet.onNotify` (`thashset.sh:638`) |
| 15 | MINOR | tokens between the operand and `--` were unspecified | validation step 3: the only legal word after the operand is `--` |
| 16 | MINOR | the D1 message named a fix that is inert under job control | the pinned text says so, and names the `--` form first |
| 17 | MINOR | `tpipe._ret` prints in a pipe RHS for the legal `--` form | the tpath contract verbatim; documented in README §3, not fixed |
| 18 | MINOR | "red against an empty tree" is not a runnable state | red-first at P0 was measured against the P0.1 skeleton (43 of 47) |
| 19 | NIT | producer stderr on the stop path breaks "nothing printed" | the silence assertions are about **TPipe's** output; stop-path producers get `2>/dev/null` |
| 20 | NIT | `stop`'s `RESULT` was unspecified | untouched — the callback may be mid-computation |
| 21 | NIT | `kk._outName`'s instance-array refusal is context-dependent | documented boundary in README §4 |
| 22 | NIT | `-c` reads as "command" | kept and explained: the letter is CR, and `--` is the only producer boundary |
| 23 | NIT | no record ordinal for the callback | `TPIPE_INDEX`, a frame-local variable — a second positional would break `printf '%s\n'`-style callbacks |

Twenty-odd further claims the critic verified as **correct** are listed at the
end of `PLAN.md` §8 so that no later phase re-probes them.

## 12. D6 final — the subshell ruling of 2026-09-15, and its probes

D1 (refuse the stdin form in a subshell, rc 2) and the first D6 (allow the `--`
form with a `kk.debug` line) were the design as shipped at P2. The owner replaced
both with a single rule in a nine-answer ruling — `PLAN.md` §2.0 **D6 final**,
summarised for callers in [../README.md §3](../README.md#3-a-sink-in-a-subshell--d6-final):
**nothing is refused**; one `kk.warn` line where the loss is *certain*; two
per-call silencers (`-s`, `KK_SUBSHELL_OK=1`); and `TPipe.each` stops printing
`RESULT` altogether.

The probe script is `scratchpad`-local and reproduced here; it takes the path of
a `tpipe.sh` so the two states can be measured side by side. Output below is from
**2026-09-15**, run against the P2 unit ("before") and the P3 unit ("after"), on
bash **5.2.37** (msys) and **5.3.9** (cygwin) — both bashes printed identical
lines, so the tables are not duplicated.

```bash
source "$1"                       # $1 = the tpipe.sh under test
class PRec … PRec.onLine() { N=$(( N + 1 )); } ; build PRec ; PRec.new R
class PStat ; public ; static proc onLine ; end ; build PStat
fmt() { printf 'F:%s\n' "$1"; }   ; p2() { printf 'a\nb\n'; }
```

**Probe 1 — the `$( )` count leak on `each` (Q7).** `each`'s stdout belongs to
the callback, but `tpipe._ret` used to append the record count to it in every
subshell position:

| call | before (P2) | after (P3) |
|---|---|---|
| `x="$(TPipe.each fmt -- p2)"` | `$'F:a\nF:b\n2'` | `$'F:a\nF:b'` |
| `TPipe.each fmt -- p2 \| cat` | `$'F:a\nF:b\n2'` | `$'F:a\nF:b'` |
| direct call, then `$RESULT` | `2` | `2` |

The third row is the one that had to stay: the count is still the member's
answer, it is simply never written to a stream.

**Probe 2 — the stdin form as the right-hand side of a pipe (Q1, Q2).**

```
before:  { printf 'x\ny\n' | TPipe.each R.onLine; }   rc=2   parent R.N=0   stderr: (empty)
after:   { printf 'x\ny\n' | TPipe.each R.onLine; }   rc=0   parent R.N=0   stderr:
Warning: TPipe.each: the instance member R.onLine runs inside a subshell (BASH_SUBSHELL=1) — the calling shell will not see it; in a pipeline use `shopt -s lastpipe` (non-interactive scripts) or the `TPipe.each CB -- CMD ...` form at top level; if the subshell scope is intended, pass -s or set KK_SUBSHELL_OK=1
```

`R.N` is `0` in the parent in **both** columns — that is the whole point, and it
is why a warning replaced a refusal rather than the state loss being "fixed".
What changed is that the records now arrive (the callback ran twice, in the
subshell), the member answers rc 0, and the caller is told once, on stderr, with
the debug switch **off**.

**Probe 3 — callback-kind detection.** The expression the unit uses is
`[[ $cb == *.* ]] && declare -p "${cb%%.*}_data"`, a builtin and no fork, run
only on the warning path:

| callback | `${cb%%.*}_data` exists? | treated as |
|---|---|---|
| `R.onLine` (instance member) | yes (`R_data`) | **instance** → warns |
| `PStat.onLine` (static member) | no | plain → silent |
| `fmt` (plain function) | no dot at all | plain → silent |

A static class has no per-instance array, which is exactly the distinction the
rule needs: `TPipe.count` used as a callback name is a static member and must not
warn.

**Probe 4 — the silencers, on `toArray` under `$( )`.** Stderr line counts,
after:

| call | RESULT printed | our stderr lines |
|---|---|---|
| `$(TPipe.toArray A -- p2)` | `2` | **1** |
| `$(TPipe.toArray -s A -- p2)` | `2` | 0 |
| `$(KK_SUBSHELL_OK=1 TPipe.toArray A -- p2)` | `2` | 0 |
| `$(VERBOSE_KKLASS=quiet TPipe.toArray A -- p2)` | `2` | 0 |
| `$(TPipe.count -- p2)` | `2` | 0 |

`RESULT` is `2` on every row: a silencer touches the warning and nothing else.
In the **before** column the `-s` row read `rc 2, RESULT=''` — `-s` was an
unknown flag then, which is also the cheapest way for a caller to tell the two
versions apart.

**Why the line is `kk.warn` and not `kk.debug` (Q6).** An error explains an
answer the caller already has; a warning says the answer is right and the effect
is not. A caller who never sets `VERBOSE_KKLASS=debug` is precisely the caller
who would lose state in silence, so the warning channel is opt-**out**:
printed at every level except `quiet`. The helper lives in `kkore/klib.sh` next
to `kk.debug`, and the three-level contract is written up once in
[kcl/README.md §1.2](../../README.md#12-errors) — TPipe follows a corpus rule
rather than inventing an exception.

## 13. What the worker phases found on top

Three findings came out of implementation rather than review, and all three
changed the unit:

| phase | finding |
|---|---|
| P0 | `declare -F` accepts `--` (§7). The record counter also had to live in `__tpi_n` with `TPIPE_INDEX` as a **mirror**, so that a callback assigning `TPIPE_INDEX` cannot corrupt `RESULT` |
| P1 | the inline `$'\r'` lost by `build` (§8) — `-c` was a silent no-op as shipped at P0 |
| P1 | `mapfile` into a `declare -i` target succeeds and rewrites every record arithmetically (§9) — added to the refusal set, which the critic's list had as assoc/readonly only. `TPIPE_INDEX` was added as a third reserved out-name prefix for `kk._outName`, because every sink shadows it with a `local` and a nameref bound to that name would fill the sink's own slot |
| P3 | `kkore/tests/001_KKLibTests.sh` ended with `rm -rf "$SCRIPT_DIR/.tmp"` — the fixture directory of the **whole suite**. With ktests' default 8 workers it wiped the directory out from under whichever file was still running; it stayed invisible only while that file happened to finish last, and surfaced the moment `007_DebugAndOutName` grew its `kk.warn` cases and outlived it. Fixed to `rm -f "$temp_file"` (§12 of this phase's report) |

## 14. Where to look next

* **[../README.md](../README.md)** — the API, the contract, the traps and the
  measured cost table. The normative page.
* **[../TEST_COVERAGE_NOTES.md](../TEST_COVERAGE_NOTES.md)** — every case of
  `001`–`005`, with the pin or finding it closes.
* **[../PLAN.md](../PLAN.md)** — the plan this unit was built from: §1 scoping,
  §2 design decisions D1–D6 (**D6 final**, the owner's nine answers, supersedes
  D1), §3 the pinned facts F1–F16, §4 the test model, §6 the bash traps, §8 the
  critic pass.
* **[../tpipe_ledger.json](../tpipe_ledger.json)** — the phase journal: what each
  phase closed, the red-first counts, the gate numbers and the commits.
* **[../bench.sh](../bench.sh)** — the numbers, re-runnable.
