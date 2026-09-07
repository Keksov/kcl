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
boolean conventions, and it is being rolled out unit by unit by the phased plan
in `PLAN.md`. Where a unit still deviates, `PLAN.md` names the phase that closes
the gap; a deviation that is meant to stay is documented in that unit's README.

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

The name is validated: it must be a plain identifier, and it must not be one of
the framework's reserved names — `this`, `__inst__`, `__class__`, `RESULT`,
`REPLY`, `IFS`, anything starting with `__kk_`, or the receiving instance's own
`<inst>_data` / `<inst>_class` / `<inst>_items`. A bad name is rc 2, and nothing
is written.

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

| Unit | Ported class(es) | Kind |
|---|---|---|
| [dateutils](dateutils/) | `DateUtils` | static |
| [math](math/) | `Math` | static (+ awk float engine) |
| [tarray](tarray/) | `TArray` | static |
| [tcustomapplication](tcustomapplication/) | `TCustomApplication` | instance |
| [tdictionary](tdictionary/) | `TDictionary`, `TObjectDictionary` | instance |
| [tdirectory](tdirectory/) | `TDirectory` | static |
| [tfile](tfile/) | `TFile` | static |
| [thashset](thashset/) | `THashSet` | instance |
| [tinifile](tinifile/) | `TIniFile`, `TMemIniFile` | instance |
| [tlist](tlist/) | `TList` | instance |
| [tobjectlist](tobjectlist/) | `TObjectList` | instance |
| [tpath](tpath/) | `TPath` | static |
| [tqueuestack](tqueuestack/) | `TQueue`, `TStack`, `TObjectQueue`, `TObjectStack` | instance |
| [tregex](tregex/) | `TRegEx` | static |
| [tstopwatch](tstopwatch/) | `TStopwatch` | instance |
| [tstringhelper](tstringhelper/) | `TStringHelper` | static |
| [tstringlist](tstringlist/) | `TStringList` | instance |
| [fpjson](fpjson/) | `fpjson` | planned |

Each unit's README documents its API and any deviation from the contract above;
`docs/*.md` inside a unit is upstream FPC/Delphi reference material and covers
members the port may not have.

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
