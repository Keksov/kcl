# kcl — Free Pascal RTL/FCL classes, ported to bash

kcl is a set of bash ports of Free Pascal RTL/FCL units, built on the
[kklass](../kklass) OOP framework and the [kkore](../kkore) helpers. Each unit
lives in its own directory (`kcl/<unit>/<unit>.sh`), has its own test suite
(`kcl/<unit>/tests/tests.sh`) and its own ledger (`<unit>_ledger.json`).

```bash
source kcl/tlist/tlist.sh          # the unit sources kklass itself
TList.new L
L.Add alpha
L.Get 0; printf '%s\n' "$RESULT"   # -> alpha
L.delete
```

---

## 1. The kcl contract

This section is the contract every unit is held to. It is **normative, not
descriptive**: it was written with the 2026-09-06 review (`REVIEW.md`), which
found the corpus using three different error conventions and five different
boolean conventions, and it was rolled out unit by unit by the phased plan in
`PLAN.md` (phases P1–P8, all landed). **Every implemented unit now meets it**,
bar a handful of deviations that are meant to stay: each one is named in the
table in section 2 and spelled out in that unit's own README.

### 1.1 Returning a value

A member returns through **`RESULT`**, never through stdout:

```bash
L.Get 3            # direct call: prints NOTHING, sets RESULT
use "$RESULT"
v="$(L.Get 3)"     # inside $( ): prints the value exactly once
```

`$( )` forks a subshell — 1–16 ms on a large shell against 0.2–0.7 ms for the
direct call — and any mutation the member makes is lost with the subshell. Use
the direct form in hot paths and reach for `$( )` only when a subshell is what
you actually want.

Values are **data**: they round-trip verbatim, including values that look like
`echo` options (`-e`, `-n`, `-neE`), embedded newlines and backslashes. Emit
them with `printf '%s'`, never `echo`.

Static (class) methods that mutate static properties leave their value in
`REPLY` as well, because `$(Class.m)` would run them in a subshell and throw the
mutation away: call them as `Class.m >/dev/null` and read `$REPLY`.

**A static unit reaches this contract through `static proc`, not `static
func`.** kklass's *thin* static dispatcher — the one a class without static
variables receives — re-prints `kk._return`'s value **unconditionally**, i.e.
on a direct call too, so a `static func` echoes on every call. The pattern the
converted static units use (P3: tpath, tfile, tdirectory; `tregex` records the
same measurement) is a `static proc` plus a two-line unit-local helper that is
`kk._return`'s contract without the dispatcher's printf:

```bash
unit._ret() {                       # $1 = value, $2 = exit status (default 0)
    RESULT="$1"
    if (( BASH_SUBSHELL > 0 )); then printf '%s' "$1"; fi
    return "${2:-0}"
}
```

An instance `func` needs none of this — `kk._return` is already correct there.

### 1.2 Errors

* **rc 1** and **`RESULT=""`** — nothing is printed on stdout or stderr.
* A diagnostic goes to stderr **only** under `VERBOSE_KKLASS=debug`.
* rc 2 is reserved for a malformed *call* (a bad output-array name, a name that
  is not an identifier), as opposed to a value the caller may legitimately try.

The caller decides whether a miss is an error; the unit never exits, never
prints, and never leaves partial state behind.

The diagnostic goes through the shared helper in
[`kkore/klib.sh`](../kkore/klib.sh), so the switch is spelled one way and the
message is data:

```bash
kk.debug "Error: TList.Get: index out of bounds"   # stderr only under the switch
```

`kk.debug` **always returns 0**. The hand-written `[[ "${VERBOSE_KKLASS:-}" ==
"debug" ]] && echo … >&2` it replaces returns 1 with the switch off, which
silently becomes the member's own exit status when it is the last statement of
a function (section 1.4).

### 1.3 Boolean answers

A predicate answers with its **exit status**, not with a printed word and not
with `RESULT`:

```bash
if D.ContainsKey "$k"; then ... fi
h.Contains x || h.Add x
```

Under `set -e` a plain `Obj.Pred` with a false answer aborts the script, so a
boolean member is always called from an `if`, a `&&`/`||`, or a `!` — that is
bash's rule for every command, and it is the price of rc-based booleans.

### 1.4 `set -e` and `set -u`

Every unit is sourceable and usable from a script that runs `set -eu`:

* re-source guards read `${_X_SOURCED:-}`, never `$_X_SOURCED`;
* indirect reads of optional metadata use `${!var:-}`;
* optional positional parameters use `${2:-}`;
* a bare arithmetic statement ends with `|| :` — **any** `(( … ))` used as a
  statement returns 1 when the expression evaluates to 0, which aborts the
  caller: `(( i -= 1 ))` on the last step, `(( x++ ))` when `x` was 0,
  `(( n = 0 ))` always. Inside `if`/`while`/`for` the status is the point and
  no `|| :` belongs there;
* a conditional action is `if (( c )); then a; fi`, not `(( c )) && a` — the
  `&&` form returns 1 whenever the condition is false;
* no member ends on a trailing `cmd && cmd` list whose last command may be false.

Every unit suite carries a `NNN_Contract.sh` that loads the unit and exercises
its main path under `set -eu`.

### 1.5 Numeric arguments

Any index, count or number that comes from the caller goes through the shared
guard in [`kkore/klib.sh`](../kkore/klib.sh) **before** it reaches `(( ))`,
`${!x}` or an external tool:

```bash
kk.isInt "$1" || return 1          # normalised value in $__KK_INT
kk.isInt "$1" idx || return 1      # ... and in $idx
kk.isNum "$2" || return 1          # floats: value in $__KK_NUM
```

* `kk.isInt` accepts an optional sign and decimal digits only, strips a leading
  `+` and leading zeros (`08` → `8`, the `10#` problem behind `encodeDate 2011
  08 09`), and rejects anything outside int64, which `(( ))` would wrap
  silently.
* `kk.isNum` additionally accepts a fraction and an exponent (`.5`, `-2.5E-10`)
  and leaves the digits verbatim for the float engine. `inf`/`nan` are *not*
  numbers here; the math unit normalises those tokens itself.
* Both are silent on every path, fork-free, and never expand or evaluate their
  argument. rc 1 = rejected value, rc 2 = malformed output-variable name.
* `OUTVAR` must be a plain identifier outside the reserved `__kk_`/`__KK_` space.
  bash scopes locals *dynamically*, so an `OUTVAR` that collides with one of the
  guard's own locals would write that local and still report success; the guards'
  locals therefore all carry the `__kk_` prefix and that prefix is refused (rc 2).

This is not a style rule. Without the guard `L.Get 'x[$(touch pwn)]'` *executes*
the command substitution inside the arithmetic evaluation, and `L.Get abc`
silently resolves to element 0.

### 1.6 Locale

kcl assumes a **UTF-8** locale: `${#s}` counts characters, `${s,,}` does not
corrupt multi-byte text, `.` in an ERE matches one character. The test runners
pin `LC_ALL=C.UTF-8` (in `ktests/ktest.sh`), and each unit self-heals a bare
environment at load time:

```bash
# Character semantics are part of this unit's contract; an empty environment
# means the C locale, where ${#s} counts bytes and ${s,,} corrupts UTF-8.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi
```

A unit that deliberately needs byte semantics (a lexer, a byte-exact file
reader) pins `LC_ALL=C` **locally**, around the smallest possible region.

### 1.7 Output arrays

A member that returns a sequence takes the **name** of a caller array and writes
into it by nameref, returning the element count in `RESULT`:

```bash
declare -a parts
str.split "$s" ',' parts       # RESULT = number of parts
```

The name is validated **before** the nameref is bound: it must be a plain
identifier, and it must not be one of the framework's reserved names — `this`,
`__inst__`, `__class__`, `RESULT`, `REPLY`, `IFS`, `state`, anything starting
with `__kk_`/`__KK_`, or the receiving instance's own `<inst>_data` /
`<inst>_class` / `<inst>_items`. A bad name is rc 2, and nothing is written.

`state` is on that list because kklass binds it as a nameref onto
`${inst}_data` in **every** member frame, so an output array called `state`
could never reach the caller from inside an instance member.

That rule is the shared helper in [`kkore/klib.sh`](../kkore/klib.sh); a unit
passes its own local-variable prefixes, because bash scopes locals
**dynamically** and an output name equal to one of them would bind the caller's
array to the unit's own scratch:

```bash
kk._outName "$1" __tqs_ || { kk._return ""; return 2; }
```

A unit with more per-instance arrays than the three above (`tqueuestack`'s
`_qhead`/`_nhook`, `tinifile`'s twelve), or with extra reserved names of its own
(`tregex`'s `RESULT_INDEX`…, `tinifile`'s `state`), checks those itself and
delegates the rest. `local -n out="$1"` on an unchecked name prints a bash
diagnostic and carries on with rc 0 — that is what this exists to prevent.

### 1.8 No forks in hot paths

A fork copies the whole shell: 1–16 ms once a few hundred objects exist, against
0.2–0.7 ms for a direct call. Inside a member there is therefore no `$( )`, no
pipe, and no external command on a path that runs per element — `${var//…}`,
`${var%%…}`, `printf -v`, `read -r`, `[[ ]]` and `(( ))` cover almost everything.
`printf '%(%s)T'` replaces `date`, and a nameref replaces `eval`. External tools
are for what bash genuinely cannot do (`stat`, `realpath`, the awk float
engine), and then once per call, not once per element.

### 1.9 Lifecycle

An instance is `<inst>_data` + `<inst>_class` + the `<inst>.<member>()` wrappers;
`obj.delete` frees exactly those. **Any extra per-instance array a unit creates
itself** (`${inst}_items`, `${inst}_names`, …) is the unit's own responsibility
and must be released in its destructor — otherwise the storage leaks and a new
instance that reuses the name starts out pre-filled.

Temporary files are removed on the path that created them and, for anything that
outlives a call, by an `EXIT` trap.

---

## 2. Units

Seventeen units are implemented; `fpjson` is planned. **Kind** is how the unit
is called: a *static* unit has one class whose members are called on the class
(`tpath.getFileName x`), an *instance* unit is constructed (`TList.new L`) and
freed (`L.delete`). **Contract** says which of the section 1 rules the unit
meets after the phased rollout in `PLAN.md`, and names every deviation that is
meant to stay; a unit marked "§1 in full" satisfies 1.1–1.9 with no exception.

| Unit | Ported class(es) | Kind | Contract |
|---|---|---|---|
| [dateutils](dateutils/README.md) | `DateUtils` (185 members) | static | §1 in full (P1, P6). Deviations, all FPC-checked: `TryISOStrToDateTime` rejects `2011` / `20110326` / `T19:25` because FPC splits ISO strings **by position** (`dateutil.inc:2849`) — the review's G3-09 was wrong about this; `tryISO8601ToDate` still accepts a date-only string, which FPC rejects; a boolean member reports a non-numeric argument as rc 1 + `RESULT=''`, not as `false` |
| [math](math/README.md) | `Math` (123 members) | static (+ awk float engine) | §1 in full (P1, P7). Deviations: `sumInt` answers the Double on overflow where FPC's Int64 `SumInt` wraps (`math.pp:1224`); FPU/precision control (Tier C) is wontfix — getters report the default mode, setters rc 1; the engine is not called through `read -t` on the hot path (R11 letter, see P7 deviations) |
| [tarray](tarray/README.md) | `TArray` (`TArrayHelper<T>`) | static | §1 in full (P1, P2). Deviation: `min`/`max` are deliberately not strict about the comparator slot — the positional after it is a free-form default value, so a non-function token there is data (G1-12) |
| [tcustomapplication](tcustomapplication/README.md) | `TCustomApplication` (FCL `custapp`) | instance | §1 in full (P1, P4); the option parser is a line-by-line port of FPC 3.2.2 `custapp.pp` (D4). Deviations: the constructor defaults `StopOnException=true`, `ExceptionExitCode=1`, `Title='Application'` where FPC leaves `False`, `0`, `''`; `GetNonOptions` answers rc 1 + `RESULT=''` where FPC raises `EListError`; `Log` writes to stderr; `GetOptionValues` returns FPC's order, which is reverse command-line order (R10) |
| [tdictionary](tdictionary/README.md) | `TDictionary`, `TObjectDictionary` | instance | §1 in full (P1, P2). Note: `AddOrSetValue k <same owned handle>` frees the handle, as FPC does (R4) |
| [tdirectory](tdirectory/README.md) | `TDirectory` (Delphi `System.IOUtils`) | static | §1 in full (P1, P3). Deviations are the platform ones shared with tpath/tfile: `/` is the separator (D5), listings include dot-entries and recursion does not descend into a directory symlink (R13) |
| [tfile](tfile/README.md) | `TFile` (Delphi `System.IOUtils`) | static | §1 in full (P1, P3). Deviations: creation time is rc 1 (no POSIX setter); `readAllTextVar NAME` is a kcl addition — the fork-free reader that keeps trailing newlines (R13) |
| [thashset](thashset/README.md) | `THashSet` | instance | §1 in full **for what is implemented**. The unit is at **P1 of its own roadmap** (`thashset_ledger.json`): the membership core, `ToArray`, `ForEach` and `Assign` are real; P2–P4 (set algebra, `TObjectHashSet`, bench/docs) are not written yet |
| [tinifile](tinifile/README.md) | `TIniFile`, `TMemIniFile` | instance | §1 in full (P1, P8). Deviations: `\` in a path is normalised to `/` for **every** file operation, not only for the directory calculation (cygwin's bash does not translate it); write-side validation is hybrid — the loader stays FPC-verbatim, the writer rejects what an FPC reader would re-interpret (R6) |
| [tlist](tlist/README.md) | `TList` | instance | §1 in full (P1, P2). Open item `P2-F1`: `BatchInsert`/`BatchDelete` are `proc`, so the count they assign to `RESULT` never reaches the caller; the README documents them as rc-only until the owner picks `func` or drops the assignment |
| [tobjectlist](tobjectlist/README.md) | `TObjectList` | instance | §1 in full (P1, P2). Inherits tlist's `P2-F1` for the two batch members |
| [tpath](tpath/README.md) | `TPath` (Delphi `System.IOUtils`) | static | §1 in full (P1, P3). Deviation: `DirectorySeparatorChar='/'` on MSYS/cygwin (D5); the parsers accept `\` on input |
| [tqueuestack](tqueuestack/README.md) | `TQueue`, `TStack`, `TObjectQueue`, `TObjectStack` | instance | §1 in full (P1, P2). Note: a rejected constructor token creates the instance **with defaults** and answers rc 1, the same in both owning classes (R3) |
| [tregex](tregex/README.md) | `TRegEx` (Delphi `System.RegularExpressions`) | static | §1 with one named exception: the three scalar members (`escape`, `replace`, `replaceCb`) set `RESULT` **and** echo their result, so `$( )` stays ergonomic — §1.1 otherwise holds and the four silent members are call-direct. Deviation by construction: the **engine is bash POSIX ERE**, not PCRE — no lazy quantifiers, no lookaround, no `\b`, no named groups; the full delta is `docs/ERE-vs-PCRE.md`. `T4` (an anchored zero-length match) is closed by documentation and tests only (R12) |
| [tstopwatch](tstopwatch/README.md) | `TStopwatch` (Delphi `System.Diagnostics`) | instance | §1 in full (P1, P6). Deviation: no `TTimeSpan` — the numeric getters (µs/ms/s/ticks) are the whole surface |
| [tstringhelper](tstringhelper/README.md) | `TStringHelper` (57 members) | static | §1 in full (P1, P5). Open item `P5-F1`: `compare`, `compareOrdinal` and `compareTo` compare the **whole** strings, where FPC's `Compare` is a prefix comparison over `min(Length(A),Length(B))`. Other deviations (all in the unit README §3): `format` is bash `printf`, `parse` is the identity, integer range checks reject instead of truncating |
| [tstringlist](tstringlist/README.md) | `TStringList` | instance | §1 in full (P1, P2). Inherits tlist's `P2-F1` for the two batch members |
| [fpjson](fpjson/) | `fpjson` | **planned** | Not implemented. `fpjson/PLAN.md` is a DRAFT to be re-written by phase P10 under decision D8 (handle model + windowed regex lexer) |

### How to read a unit

Every unit directory holds the same four kinds of file, and they answer
different questions:

* **`README.md` — the API and the contract.** The normative description of what
  this unit actually implements, how each member is called, and every deviation
  from section 1 or from FPC. This is the file to read and the file to trust.
* **`docs/*.md` — upstream reference material.** A scrape or transcription of
  the FPC/Delphi documentation for the class being ported, kept so the port can
  be checked against it. Each one opens with a header saying what is **ported**,
  what is on the **roadmap**, and what is **wontfix**, because these pages
  describe members the port may not have. Where the page and the port disagree,
  the port's README wins — and where the page and FPC 3.2.2 disagree, FPC wins.
* **`TEST_COVERAGE_NOTES.md` — what the tests pin.** Present in the units that
  have one: the map from member to the assertions that hold it in place, and
  the gaps that are known and deliberate.
* **`<unit>_ledger.json` — the history.** The machine journal of the unit's own
  phases: what each one closed, which test proved it, what was left as
  `wontfix`, and the commit it landed in.

Paths on MSYS/cygwin use `/` as the separator (`DirectorySeparatorChar='/'`);
the tpath parsers accept `\` on input as well.

---

## 3. Running the tests

```bash
bash kcl/<unit>/tests/tests.sh                    # one unit
bash kcl/<unit>/tests/tests.sh --verbosity info   # ... showing each assertion
bash tests/tests.sh                               # the whole kbool corpus
```

Suites must be run **one at a time** — they share `tests/.ckk` and `/tmp` names.
Read the result by grepping **all** `[FAIL]` lines, not by looking at the tail of
the output. The second bash on this machine is started as

```bash
PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe tests/tests.sh
```

— without the `PATH` prefix the runner's child `bash` is the other build and the
suite reports 0 tests.

---

## 4. Plan and review

`REVIEW.md` holds the 2026-09-06 deep review (findings with IDs), `PLAN.md` the
phased fix plan and the owner's decisions D1–D8, `kcl_ledger.json` the machine
journal, and `docs/review-2026-09-06/` the eight full reviewer reports with
`file:line`, repro commands and their scripts.
