# kcl — Free Pascal RTL/FCL classes, ported to bash

kcl is a set of bash ports of Free Pascal RTL/FCL units, built on the
[kklass](../kklass) OOP framework and the [kkore](../kkore) helpers. Every
file is a kbool **unit** (section 1.10): 29 units in 26 folders — each folder
`kcl/<unit>/` holds `<unit>.sh`, except the thttpserver package, whose folder
holds four (`thttpmessage`, `thttprouter`, `thttpserver`, `thttpapplication`).
Each folder has its own test suite (`kcl/<unit>/tests/tests.sh`) and its own
ledger (`<unit>_ledger.json`).

```bash
source /path/to/kbool/kbool.sh     # once per script (see the kbool README)
kk.uses tlist                      # a unit by NAME; it loads kklass itself
TList.new L
L.Add alpha
L.Get 0; printf '%s\n' "$RESULT"   # -> alpha
L.delete
```

`source kcl/tlist/tlist.sh` works too: the unit's header loads `kbool.sh` when
it is not loaded yet, and a unit is loaded once however it is reached. The
loader, the search path and the configuration are described in the
[kbool README](../README.md) and the [kkore reference](../kkore/README.md).

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

`VERBOSE_KKLASS` has **three levels** — `quiet`, unset (the default) and
`debug` — because a unit has two things to say. An **error** is `kk.debug`:
the call did not work (rc 1 + `RESULT=""`, or rc 2 for a malformed call), and
the reason is printed only under `debug`. A **warning** is `kk.warn`: the call
*worked* — rc and `RESULT` are exactly what the contract promises — but it very
likely did not do what the caller meant, and neither the rc nor the value can
say so, so the line is printed **always except under `quiet`** and changes
nothing else. A unit that warns documents the exact line and the **per-call**
way to silence it (tpipe's subshell warning: the `-s` flag, or
`KK_SUBSHELL_OK=1`).

```bash
kk.warn "Warning: TPipe.toArray: the array A is filled inside a subshell …"
VERBOSE_KKLASS=quiet   # the corpus-wide off switch for every warning
```

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

* the unit header (section 1.10) is `set -eu` safe: a first load runs the
  unit, every later `source` or `kk.uses` returns 0 without running it (it
  replaced the hand-written `${_X_SOURCED:-}` re-source guards, uses phase U4);
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

### 1.10 Every unit is a kbool unit

A kcl unit file is a kbool unit (kklass/USES_PLAN.md, rolled out in phase U4;
the loader's rules: [kkore/README.md](../kkore/README.md)). Its shape, checked
for every unit by `kcl/tests` (section 3):

1. **Header.** Line 1 `#!/bin/bash`; lines 2–3 exactly the in-tree header,
   with the file stem as the unit name:

   ```bash
   #!/bin/bash
   [[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%tlist.sh}../../kbool.sh" || return
   kk.unit tlist || return $__kk_unit_rc
   ```

   then the unit's own comment block. `../../kbool.sh` is the unit's ONLY
   relative path. A unit is loaded once per shell, by a direct `source`, by
   `kk.uses` or as a dependency.
2. **No guard of its own.** The header is the guard: no `_X_SOURCED` variable.
3. **Dependencies through `kk.uses`, by name.** The kklass module the unit
   needs — `kk.uses kklass_pascal || return` (or `kklass`, `kklass_decl`) —
   and every other kcl unit by NAME, one `kk.uses NAME || return` line each,
   where the code needs it (`kk.uses tpath || return`). Never a path, never a
   kkore unit (`kbool.sh` always loads `klib`, `kerr`, `kvar`, `kcfg`).
   `kk.uses --optional X || fallback` only for a dependency the unit handles
   itself (and the row flag `optional` in `kcl/tests`). A name the unit uses —
   another unit's class, namespace or function — must come through its
   `kk.uses` closure.
4. **Helper namespaces are declared.** A file-scope function `X.name` whose X
   is neither a class of the unit nor the unit's name (`TDict.*`, `ths.*`,
   `tca.*`) needs `kk.namespace X || return` on the code line right after the
   `kk.uses` lines, with a short comment saying so; then no class or
   instance may take X. A namespace shared by a package (thttpserver's `ths`)
   is declared in every file of the package that defines `ths.*`; only files of
   one folder may share one. Lowercase helpers named like the unit (`tpipe.*`,
   `tawk.*`) are declared by the header.
5. **No folder variable, no fork.** No `X_DIR=$(cd "$(dirname …)" && pwd)`.
   While the unit loads, its folder is `KK_UNIT_DIR`; code that needs the folder
   at run time keeps a fork-free copy taken before the first `kk.uses`
   (`MATH_DIR=$KK_UNIT_DIR`; row flag `rundir`).
6. **No file-scope `local` / `declare` without `-g`.** A unit loaded by
   `kk.uses` runs inside a function: they would become the loader's locals
   (the unit lint rejects them).
7. **`readonly` once per process.** A unit that assigns readonly globals
   wraps the assignments AND the `readonly` statement, keyed on one of its own
   names, so `kk.unit --forget U` + a re-source (the development hatch) does not
   fail with `readonly variable` — which under `set -e` exits the caller:

   ```bash
   if [[ -z ${__TPATH_BS+x} || ${__TPATH_BS@a} != *r* ]]; then
       __TPATH_BS='\'
       ...
       readonly __TPATH_BS ...
   fi
   ```

   (`${X@a}` of an unset name aborts under `set -u`, hence `${X+x}` first.)
   Mutable process state that must survive such a reload — a running
   co-process's pid and fds (math), a registry other units extend at their
   load (tutil's `TUTIL_OUT_PREFIXES`) — is set once per process too:
   `if [[ -z ${X+x} ]]; then … fi` (row flags `readonly`, `state`).
8. **Tests may keep plain `source`.** A unit suite sources its unit by path
   (`source "$TLIST_DIR/tlist.sh"`); that loads kbool and registers the
   unit like any other load.

---

## 2. Units

Twenty-nine units in twenty-six folders are implemented — one row per folder
below; the thttpserver row is a package of four units — and `fpjson` is
planned. **Kind** is how the unit is called: a *static* unit has one class
whose members are called on the class (`tpath.getFileName x`), an *instance*
unit is constructed (`TList.new L`) and freed (`L.delete`). **Contract** says
which of the section 1 rules the unit meets after the phased rollout in
`PLAN.md`, and names every deviation that is meant to stay; a unit marked "§1
in full" satisfies 1.1–1.9 with no exception. Every unit meets 1.10 (uses phase
U4, checked by `kcl/tests`).

| Unit | Ported class(es) | Kind | Contract |
|---|---|---|---|
| [dateutils](dateutils/README.md) | `DateUtils` (185 members) | static | §1 in full (P1, P6). Deviations, all FPC-checked: `TryISOStrToDateTime` rejects `2011` / `20110326` / `T19:25` because FPC splits ISO strings **by position** (`dateutil.inc:2849`) — the review's G3-09 was wrong about this; `tryISO8601ToDate` still accepts a date-only string, which FPC rejects; a boolean member reports a non-numeric argument as rc 1 + `RESULT=''`, not as `false` |
| [math](math/README.md) | `Math` (123 members) | static (+ awk float engine) | §1 in full (P1, P7). Deviations: `sumInt` answers the Double on overflow where FPC's Int64 `SumInt` wraps (`math.pp:1224`); FPU/precision control (Tier C) is wontfix — getters report the default mode, setters rc 1; the engine is not called through `read -t` on the hot path (R11 letter, see P7 deviations) |
| [tarray](tarray/README.md) | `TArray` (`TArrayHelper<T>`) | static | §1 in full (P1, P2). Deviation: `min`/`max` are deliberately not strict about the comparator slot — the positional after it is a free-form default value, so a non-function token there is data (G1-12) |
| [tawk](tawk/README.md) | **GNU Awk wrapper over [`TUtil`](tutil/README.md) (gawk 5.0.0 / 5.4.0)** — no FPC/Delphi source: `TAwk : TUtil`, typed options into a pinned argv, `program` + `addProgram` + `programFile`, verbatim `setVar` — the tool is resolved by `ktool` to an absolute path (`gawk` on FreeBSD), and with no usable tool every sink is rc 2 with `ktool`'s reason | instance (+ static `apply`) | §1 in full (P0–P1 of its own roadmap, complete) with the family's inherited deviation (a) and **named ones of its own**: (a) `run` **streams to stdout by definition** — a stream member prints, and the tool's bytes pass through untouched in every position; (b) **the sandbox is on by default and fails closed** — `--sandbox` is dropped only for the exact string `0`, so `system()`, every output redirection (`> "/dev/stderr"` and `> "/dev/stdout"` included), pipes, `\|&`, **input** redirection `getline < f` and extensions are gawk's fatal error (rc 1) unless the caller says `sandbox = 0`; (c) **a missing input file stops there** — gawk's FATAL rc 2: the earlier files' records are kept (`RESULT` = their count, rc 1, raw 2 in `lastRc`) and the later files are never read or edited, while **a directory operand is skipped** with gawk's warning and rc 0; (d) **gawk's own stderr passes through unconditionally**, its text differing between the two versions; (e) **a program's `exit N` is rc 1 silent**, the raw value (N mod 256) in `lastRc` (`exit 1`/`exit 2` get the one debug line, worded to say they may be the program's); (f) **`inPlace` and `nullData` derive `-v BINMODE=3`**, because text mode rewrites CRLF to LF on disk under in-place and strips a CR inside a NUL record — the `binary` property is never written; (g) **`setVar` is verbatim, unlike `-v`**: it emits `-v NAME=enc(VALUE)` (every `\` doubled, a newline `\n`, a leading `@` `\100`), byte-exact on both versions, while plain `-v` — still available through `addArg` — processes escapes and differs between 5.0 and 5.4; `backupSuffix` is encoded the same way; (h) **`print` terminates an unterminated last line** (it appends ORS; also under `nullData`); and `programFile` is resolved through AWKPATH (`-` is rc 2). Also: **in-place is `run` only and needs `sandbox = 0`** (the sandbox refuses the extension, so `inPlace` with the default sandbox is rc 2) — the five sinks are rc 2 with `inPlace = 1`, the extension is loaded by its **absolute** path (`-i inplace` would load a planted `./inplace.awk`), END output goes to stdout and `exit` mid-file truncates that file; **no program at all is rc 2** and an empty chunk is never emitted (gawk drops `-e ''` and compiles the first path as the program — `TAwk.apply ''` is rc 2 too); a path gawk reads as an assignment (`k=v`, `a::b=v`) is rc 2 (pass `./k=v`); the **`addArg` deny-list** follows gawk's getopt on both versions — every option that is modelled, skips the program, writes files under the sandbox, reads stdin or loses the input (`-e -f -i -l -E -F -S -o -g -h -V -C -d -p -D -M`), in short, attached, bundled and long form, **any prefix** of a long name and every **`-W long-option`** spelling, plus `-P`/`-c` while BINMODE is derived, `--`, a non-option word (it would become THE program) and a dangling `-v`/`-W`; a `setVar` name that is not an identifier, a keyword, a builtin or a gawk array is rc 2; a callback that assigns a bare `sandbox=0` or `program=` writes the instance's property, so callbacks declare `local`. `__taw_` and `_progs`/`_vnames`/`_vvals` are appended to the two out-name registries |
| [tcustomapplication](tcustomapplication/README.md) | `TCustomApplication` (FCL `custapp`) | instance | §1 in full (P1, P4); the option parser is a line-by-line port of FPC 3.2.2 `custapp.pp` (D4). Deviations: the constructor defaults `StopOnException=true`, `ExceptionExitCode=1`, `Title='Application'` where FPC leaves `False`, `0`, `''`; `GetNonOptions` answers rc 1 + `RESULT=''` where FPC raises `EListError`; `Log` writes to stderr; `GetOptionValues` returns FPC's order, which is reverse command-line order (R10) |
| [tdictionary](tdictionary/README.md) | `TDictionary`, `TObjectDictionary` | instance | §1 in full (P1, P2). Note: `AddOrSetValue k <same owned handle>` frees the handle, as FPC does (R4) |
| [tdirectory](tdirectory/README.md) | `TDirectory` (Delphi `System.IOUtils`) | static | §1 in full (P1, P3). Deviations are the platform ones shared with tpath/tfile: `/` is the separator (D5), listings include dot-entries and recursion does not descend into a directory symlink (R13) |
| [tfile](tfile/README.md) | `TFile` (Delphi `System.IOUtils`) | static | §1 in full (P1, P3). Deviations: creation time is rc 1 (no POSIX setter); `readAllTextVar NAME` is a kcl addition — the fork-free reader that keeps trailing newlines (R13); `encrypt`/`decrypt` use the KBTF1 format (HMAC-SHA256: a wrong password and tampering are detected, and the pre-KBTF1 format is refused) |
| [tfind](tfind/README.md) | **GNU findutils 4.10.0 `find` wrapper over [`TUtil`](tutil/README.md)** — no FPC/Delphi source: `TFind : TUtil`, eight typed options into a pinned argv — the tool is resolved by `ktool` to an absolute path (`gfind` on FreeBSD), and with no usable tool every sink is rc 2 with `ktool`'s reason | instance (+ static `byName`) | §1 in full (P0–P1 of its own roadmap, complete) with the family's **two inherited deviations** and **four notes of its own**: (a) `run` **streams to stdout by definition** — a stream member prints, and the tool's bytes pass through untouched in every position; (b) **a partial failure keeps the records**: a missing start point among good ones still prints the good ones' records, so the sink answers rc 1 with `RESULT` = the **real count** and `lastRc` 1 — check the rc before using the data (a **missing `newer` file is the other case**: fatal, zero records); (c) **find's own stderr passes through unconditionally**, gated by nothing and quoted per the locale, because it is the tool's stream and not ours; and (d) **`-exec CMD {} \;` whose command fails or is missing leaves find at rc 0** (stderr only) — the `{} +` form propagates it as rc 1, so a caller who needs the child's status in `lastRc` uses `+`. Also: find's grammar is the **reverse** of grep's and head's, so **start points are positional** and come first — `--` ends the *option* list only and cannot rescue one, which is why an empty start point or one matching `^[-!(]` is **rc 2** (`./-weird` works) and why `followSymlinks` is typed (`-L` is accepted only *before* the start points); **`print0 = 1` derives the sinks' `-0` and excludes every other action** — any action word among the `addArg` extras is then rc 2, because two actions interleave into one corrupted NUL record and a failing `-exec` short-circuits `-print0` away entirely; the depths go through `kk.isInt` and are emitted **normalised** (`+1` verbatim is the tool's rc 1), the opposite decision from thead/ttail where the sign is meaning; `-quit`/`-prune`/`-delete` are order-incompatible with the fixed action position and stay hand-built (`print0 = 0` plus a manual `nul`); and `-name` is **case-sensitive** on NTFS under msys. This unit also turned `tutil._badOut`'s hard-coded prefix list into the **`TUTIL_OUT_PREFIXES` registry**, with the registry's own name reserved as an out-name and a fail-closed empty registry |
| [tgrep](tgrep/README.md) | **GNU grep 3.0 wrapper over [`TUtil`](tutil/README.md)** — no FPC/Delphi source: `TGrep : TUtil`, 22 typed options into a pinned argv — the tool is resolved by `ktool` to an absolute path (`ggrep` on FreeBSD), and with no usable tool every sink is rc 2 with `ktool`'s reason | instance (+ static `search`) | §1 in full (P2–P3 of the tutil roadmap, complete) with **three named deviations**, two inherited and one its own: (a) `run` **streams to stdout by definition** — a stream member prints, and the tool's bytes pass through untouched in every position; (b) for the counting sinks **rc 1 means the tool exited non-zero** and `RESULT` still carries the record count (arrays and lists keep what was read) — check the rc, or `lastRc`, before using the data; (c) **a per-file grep failure keeps the records**: grep answers raw 2 while still delivering matches when one operand of several is unreadable, and the sink then has `RESULT` = the real count with rc 1 and `lastRc` 2. Also: **`search` implies `-r` and needs ≥ 1 path** (`grep -r` with none would search the current directory), while an instance **never** implies `-r`; `recursive` is `-r` and never `-R`, so a directory symlink found during the walk is not descended (R13). `P3-F1` (the `-Z` + `-l/-L` → `-0` derivation clearing a `nul` the caller had set) was found at P3 while writing the docs and fixed in the same phase; it is pinned by `tests/004_Argv.sh` §G |
| [thashset](thashset/README.md) | `THashSet` | instance | §1 in full (P0–P4 of its own roadmap, complete). Deviations, all deliberate and FPC-checked: `Add` and `Remove` are FPC Booleans (`:2559`/`:2566`), so the **exit status is the answer** and rc 1 is **silent** — the loud difference from `TDictionary`, whose `Add` treats a duplicate as an error; `Extract` on a miss is `RESULT=''` with **rc 0** (`Default(T)`, `:2582`), indistinguishable from extracting the `''` element — ask `Contains` first; an algebra operand that is not a live `THashSet` is rc 1 **checked by class before any mutation**, so the set is left byte-identical; a malformed **call** — an `AddRangeFromArray`/`ToArray` array name that is not usable, or an `onNotify` argument that is not a function — is rc 2. FPC declares no `TObjectHashSet`, and the sorted family (`TSortedSet`/`TSortedHashSet`) is wontfix: ordered iteration is `ToArray` + `TArray.sort` at the boundary |
| [thead](thead/README.md) | **GNU coreutils 8.32 `head` wrapper over [`TUtil`](tutil/README.md)** — no FPC/Delphi source: `THead : TUtil`, typed options into a pinned argv — the tool is resolved by `ktool` to an absolute path (`ghead` on FreeBSD; uutils >= 0.2.2 is accepted too), and with no usable tool every sink is rc 2 with `ktool`'s reason | instance (+ static `take`) | §1 in full (P0–P1 of its own roadmap, complete) with the family's **two inherited deviations** and three notes of its own: (a) `run` **streams to stdout by definition** — a stream member prints, and the tool's bytes pass through untouched in every position; (b) **a partial failure keeps the records**: `head -n 1 good missing` prints good's line and exits 1, so the sink answers rc 1 with `RESULT` = the **real count** and `lastRc` 1 — check the rc before using the data; and **head's own stderr passes through unconditionally**, gated by nothing and quoted per the locale (`'…'` under C, `‘…’` under the unit's `C.UTF-8` self-heal), because it is the tool's stream and not ours. Also: the `==> NAME <==` **headers are records** — with two or more operands they arrive through the sinks like any other line, and the leading `\n` of a later header is an empty record only when the previous file's last line was terminated (two terminated 3-line files under `-n 5` are 9 records, the same pair with the first unterminated is 8); **`zeroTerminated` with ≥ 2 paths or with `verbose` is rc 2**, because those headers stay newline-terminated under `-z` and the derived `-0` would frame a header and its whole file into one record; the count is validated by regex + a 19-digit guard and passed **verbatim** (never `kk.isInt`: `-0` means *everything* to head and `0` means *nothing*), so a suffix like `1K` is rc 2 and `addArg -n 1K` is the documented hatch — and because extras come last and head is last-flag-wins, an `addArg -n`/`-c` silently replaces `lines`/`bytes` |
| [thttpserver](thttpserver/README.md) | **kcl addition — no FPC/Delphi source** (fcl-web is a design reference only): `THttpRequest`, `THttpResponse`, `THttpRouteObject`, `THttpRouter`, `THttpTransport`, `TReplayTransport`, `TNetcatTransport`, `TSocatTransport`, `THttpServer`, `THttpApplication : TCustomApplication` — a minimal HTTP/1.0-style server on GNU netcat 0.7.1 or socat >= 1.7.4 (detected: GNU netcat first, socat where the distro's nc is another flavour) whose handlers run **in the server's own shell**, so objects live across requests; a kklass showcase | instance classes | §1 in full (P0–P3 of its own roadmap, complete) with **five named deviations**: (a) `Active = true`, `Serve` and `App.Run` **block** until the server stops; (b) a handler's **stdout goes to the server's console**, not to the client — the handler writes through the response; (c) **one request at a time, no keep-alive** — one further client waits in the pre-spawned listener, a burst gets resets (GNU nc drops its accept backlog; socat's burst behaviour is unverified — backlog item: measure it in the 004 parallel case); (d) a **KILLed** server leaves its temp dir and listeners until `ListenerTTL` (the unit installs no EXIT trap; TERM/INT are clean); (e) a write to a read-only property prints kklass's own `Error: Property 'X' is read-only`. Also: `ReadFrom` answers a parser status as **rc 0 + a value** (C20); a failed validation at send becomes a 500 with the default head; handlers declare every variable `local` and register a method of the running instance as `"$this.M"` or `"$__inst__.M"` (both are plain data since kklass R2_P8 removed the body-text rewrite). Text bodies only (a NUL is 400), 64 KiB default limit, ≈ 10 requests/s sequentially |
| [tinifile](tinifile/README.md) | `TIniFile`, `TMemIniFile` | instance | §1 in full (P1, P8). Deviations: `\` in a path is normalised to `/` for **every** file operation, not only for the directory calculation (cygwin's bash does not translate it); write-side validation is hybrid — the loader stays FPC-verbatim, the writer rejects what an FPC reader would re-interpret (R6) |
| [tlist](tlist/README.md) | `TList` | instance | §1 in full (P1, P2). Open item `P2-F1`: `BatchInsert`/`BatchDelete` are `proc`, so the count they assign to `RESULT` never reaches the caller; the README documents them as rc-only until the owner picks `func` or drops the assignment |
| [tobjectlist](tobjectlist/README.md) | `TObjectList` | instance | §1 in full (P1, P2). Inherits tlist's `P2-F1` for the two batch members |
| [tpath](tpath/README.md) | `TPath` (Delphi `System.IOUtils`) | static | §1 in full (P1, P3). Deviation: `DirectorySeparatorChar='/'` on MSYS/cygwin (D5); the parsers accept `\` on input |
| [tpipe](tpipe/README.md) | **kcl addition — no FPC/Delphi source**: `TPipe`, a stream-to-callback adaptor; on Linux every producer reports its own exit status (bash can lose it under load), external producers included since L34-F1 | static | §1 in full (P0–P3 of its own roadmap, complete) with **two named deviations**: (a) for `each`/`toArray`/`toList`/`count` **rc 1 means the producer exited non-zero**, not "no answer" — `RESULT` still carries the record count, and the array/list keep everything read before the failure (check the member's rc, or `TPipe.lastRc`, before using the data); (b) **`each` never prints `RESULT`** under `$( )` or on the LHS of a pipe — its stdout is the **callback's**, byte for byte, and the count is read from `RESULT` after a direct call (decision D6 final Q7). A sink in a subshell is **never refused**; where the loss is certain (`each` with an instance-member callback, `toArray`, `toList`) it prints one **subshell warning** through `kk.warn`, silenced per call by `-s` or `KK_SUBSHELL_OK=1` and corpus-wide by `VERBOSE_KKLASS=quiet` |
| [tqueuestack](tqueuestack/README.md) | `TQueue`, `TStack`, `TObjectQueue`, `TObjectStack` | instance | §1 in full (P1, P2). Note: a rejected constructor token creates the instance **with defaults** and answers rc 1, the same in both owning classes (R3) |
| [tregex](tregex/README.md) | `TRegEx` (Delphi `System.RegularExpressions`) | static | §1 with one named exception: the three scalar members (`escape`, `replace`, `replaceCb`) set `RESULT` **and** echo their result, so `$( )` stays ergonomic — §1.1 otherwise holds and the four silent members are call-direct. Deviation by construction: the **engine is bash POSIX ERE**, not PCRE — no lazy quantifiers, no lookaround, no `\b`, no named groups; the full delta is `docs/ERE-vs-PCRE.md`. `T4` (an anchored zero-length match) is closed by documentation and tests only (R12) |
| [tsed](tsed/README.md) | **GNU sed 4.9 wrapper over [`TUtil`](tutil/README.md)** — no FPC/Delphi source: `TSed : TUtil`, typed options into a pinned argv, `expr` + `addExpr` + `scriptFile`, and (H1) the literal replace `addReplace FROM TO [FLAGS]` with the escapers `quoteRe` / `quoteRepl` — the tool is resolved by `ktool` to an absolute path (`gsed` on FreeBSD), and with no usable tool every sink is rc 2 with `ktool`'s reason | instance (+ statics `edit`, `replace`, `replaceInFile`, `quoteRe`, `quoteRepl`) | §1 in full (P0–P1 of its own roadmap, complete) with the family's inherited deviation (a) and **five named ones of its own**, (b)–(f): (a) `run` **streams to stdout by definition** — a stream member prints, and the tool's bytes pass through untouched in every position; (b) **the sandbox is on by default and fails closed** — `--sandbox` is dropped only for the exact string `0` (every other value keeps it, the one deliberate exception to the family's "on only for `1`" rule), so `e`, `s///e`, `r`, `R`, `w`, `W` and `s///w` — the idiom `s/a/A/w /dev/stdout` included — are sed's rc 1 unless the caller says `sandbox = 0`; (c) **a missing input file keeps the other files' records**: the sink answers rc 1 with `RESULT` = the **real count** (raw 2 in `lastRc`), while an **I/O error** (raw 4 — a directory operand, a missing `-f` script, a failed backup rename) **stops at that operand**, earlier records kept and later files never read or edited; (d) **sed's own stderr passes through unconditionally**, gated by nothing and quoted per the locale; (e) **a script's `q N` / `Q N` status is rc 1 silent**, the raw value in `lastRc` (a `q1`/`q2`/`q4` gets the one debug line, worded to say it may be the script's); and (f) **`inPlace` and `nullData` derive `-b`**, because text mode rewrites CRLF to LF on disk under `-i` (even the identity) and strips a CR inside a NUL record under `-z` — the `binary` property is never written, so the wrapper has no text-mode in-place path. Also: every option is emitted **before the first `-e`** (sed compiles each `-e` as it reads it); **no script at all is rc 2** (sed would read the first path as the script; the identity is `addExpr ''`, and `TSed.edit '' f` is the identity too); **in-place is `run` only** — with `inPlace = 1`, or `--debug` among the extras, the five sinks are rc 2 and nothing runs, and `q`/`Q`/`quiet` without `p` truncate the file silently under `-i`; `backupSuffix` is attached to `-i`, `*` alone is rc 2 and `*` elsewhere is the operand **as given**, directory included; the **`addArg` deny-list** refuses, with rc 2 and a line naming the property to use, every extra sed's getopt reads as a modelled option — bundles (`-ni`), attached arguments (`-i.bak`, `-es/a/b/`), unambiguous long abbreviations (`--in=.bak`, `--expr=p`, `--sand`), the `--zero-terminated` alias — and a bare `--`, which would turn the expressions into operands; a callback that assigns a bare `sandbox=0` writes the instance's property, so callbacks declare `local`. This unit also turned `tutil._badOut`'s hard-coded suffix list into the **`TUTIL_OUT_SUFFIXES` registry** (tsed adds `_exprs _rfrom _rto _rflags`), with the registry's own name reserved and a fail-closed empty registry |
| [tstopwatch](tstopwatch/README.md) | `TStopwatch` (Delphi `System.Diagnostics`) | instance | §1 in full (P1, P6). Deviation: no `TTimeSpan` — the numeric getters (µs/ms/s/ticks) are the whole surface |
| [tstringhelper](tstringhelper/README.md) | `TStringHelper` (57 members) | static | §1 in full (P1, P5). Open item `P5-F1`: `compare`, `compareOrdinal` and `compareTo` compare the **whole** strings, where FPC's `Compare` is a prefix comparison over `min(Length(A),Length(B))`. Other deviations (all in the unit README §3): `format` is bash `printf`, `parse` is the identity, integer range checks reject instead of truncating |
| [tstringlist](tstringlist/README.md) | `TStringList` | instance | §1 in full (P1, P2). Inherits tlist's `P2-F1` for the two batch members |
| [ttail](ttail/README.md) | **GNU coreutils 8.32 `tail` wrapper over [`TUtil`](tutil/README.md)** — no FPC/Delphi source: `TTail : TUtil`, typed options into a pinned argv, plus `follow` — the tool is resolved by `ktool` to an absolute path (`gtail` on FreeBSD; uutils >= 0.2.2 is accepted too), and with no usable tool every sink is rc 2 with `ktool`'s reason | instance (+ static `take`) | §1 in full (P0–P1 of its own roadmap, complete) with **everything [thead](thead/README.md) carries** — `run` streams by definition; a partial failure keeps the records with `RESULT` = the real count and rc 1; the tool's own stderr passes through unconditionally and locale-quoted; the `==> NAME <==` headers are records (9 / 8 records for two 3-line files under `-n 5`, depending on termination); `zeroTerminated` with ≥ 2 paths or with `verbose` is rc 2; the count is regex-validated and passed verbatim (for tail `kk.isInt` would turn `+2`, *from line 2*, into `2`, *the last two*) — **plus one deviation of its own**: with `follow = 1` the sinks that can only finish at EOF are **rc 2 in the overriding member and nothing runs** (`toArray`, `count`, `toList` — the last because no kcl list's `.Add` calls `TPipe.stop`), while `each` and `first` **stream until the consumer calls `TPipe.stop`** (the stop path then ends tail with raw 143 → member rc 0, `lastRc` 143) and `run` streams until the caller kills it. There is no timeout and no cancellation from outside: a caller who cannot guarantee a stop uses `run` under an external `timeout`, and `addArg --pid=PID` is the only shape in which `-f` ends by itself |
| [tutil](tutil/README.md) | **kcl addition — FPC `fcl-process` `TProcess` kinship, no line-by-line source**: `TUtil`, the CLI-tool wrapper base and a concrete generic argv runner; `tutil._gnu FAMILY` hands the wrappers the absolute path `ktool` resolved (g-names on FreeBSD), and with no usable tool their sinks are rc 2 with `ktool`'s reason | instance | §1 in full (P0–P3 of its own roadmap, complete) with **two named deviations**: (a) `run` **streams to stdout by definition** — every other member answers in `RESULT` and prints nothing, but a stream member prints, and the tool's stdout is inherited byte-for-byte in every position (`$( )`, `<( )`, the LHS of a pipe) with no framework bytes leaked; (b) for the counting sinks `each`/`toArray`/`toList`/`count`, **rc 1 means the tool exited non-zero** and `RESULT` still carries the record count — arrays and lists keep everything that was read, so a caller who wants all-or-nothing tests the rc first (inherited from [tpipe](tpipe/README.md); `first` does **not** deviate — its rc 1 means "there was no record", whatever the tool's own status). The member-by-member `TProcess` comparison, with everything that is wontfix and why, is [tutil/docs/TUtil.md](tutil/docs/TUtil.md) |
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
the output. To run under a second bash, put its folder first on `PATH` and start
the runner with it:

```bash
PATH="/opt/bash53/bin:$PATH" /opt/bash53/bin/bash kcl/tlist/tests/tests.sh
```

— without the `PATH` prefix the runner's child `bash` is the other build (see
the [kbool README](../README.md#running-the-tests)).

The runner gives every test file an empty `HOME` and no kbool configuration
(`KBOOL_CONFIG`, `KBOOL_HOME`, `USERPROFILE`, `ProgramData` unset, `BASH_ENV`
emptied, the `/etc/kbool` level pointed at a missing folder): a developer's
`~/.kbool/config` cannot change a result.

### `kcl/tests` — the unit shape of every unit

```bash
bash kcl/tests/tests.sh                           # 179 tests, ~75 s threaded
```

One kcl-level suite checks section 1.10 for all 29 units, so the unit suites
keep their own concerns and totals:

* `kcl_units.sh` — the table `KCL_UNITS`, one row per unit
  `UNIT|NAMESPACES|FLAGS|DIR` (the `kk.namespace` names; flags `rundir`,
  `readonly`, `state`, `optional`; the folder when it is not `UNIT`), and the
  shared checks. Not a test file.
* `001_UnitFiles.sh` — every row statically: the header on lines 2–3, no old
  guard / folder variable / hard path / fork / `source` statement, the
  `kk.uses … || return` and `kk.namespace … || return` forms and place, a
  census of file-scope `X.name` functions against the classes, the unit name
  and the row's namespaces, the lint, `--optional` only with its flag, every
  cross-unit reference inside the `kk.uses` closure, rows ↔ stubs.
* `NNN_<UNIT>.sh` — one runtime stub per row (101–107, 201–204, 301–305,
  401–408, 501–505: the migration groups), copies of `101_tstopwatch.sh`;
  the unit is the stem after `NNN_`; a stub may add checks of its own unit
  after the shared ones (102 tpath, 202 math, 402 tutil, 502 thttpmessage).
  Each loads its unit once in a fresh shell under `set -eu` and checks: loaded once by an absolute,
  a relative and a by-name load (a sentinel function stays), its classes filed
  under it, `kk.unit --forget` + reload clean for `readonly` / `state` rows, a
  runtime census of function prefixes, no old globals, its name and namespaces
  taken (`.new` / `defineClass` refused), a refused `kk.namespace` fails the
  load, and — for units that use another unit of the table — a mixed load
  behind a plain-sourced dependency.

### Adding a unit

1. `kcl/<unit>/<unit>.sh` with the section 1.10 shape: shebang, the two
   header lines, the comment block, `kk.uses kklass_pascal || return` and the
   kcl units it needs by name, `kk.namespace` for helper prefixes; the §1.6
   locale self-heal; no `X_DIR`, no fork, no path, no file-scope `local`;
   readonly constants and reload-surviving state once per process.
2. Its suite `kcl/<unit>/tests/tests.sh` (a copy of a sibling's runner) with
   a `NNN_Contract.sh` that loads the unit under `set -eu` (§1.4).
3. A row in `kcl/tests/kcl_units.sh` `KCL_UNITS` and a stub
   `kcl/tests/NNN_<unit>.sh` (a copy of `101_tstopwatch.sh`, a new number);
   `001` fails while one exists without the other.
4. `bash kcl/tests/tests.sh` and the unit's own suite on both bashes; a row in
   the section 2 table; its README, TEST_COVERAGE_NOTES and ledger.
5. A unit outside `kcl/` (your own project) uses the user header with
   `KBOOL_HOME` instead and a `unitpath` entry in its project file — see the
   [kbool reference](../docs/reference.md#units).

---

## 4. Plan and review

`REVIEW.md` holds the 2026-09-06 deep review (findings with IDs), `PLAN.md` the
phased fix plan and the owner's decisions D1–D8, `kcl_ledger.json` the machine
journal, and `docs/review-2026-09-06/` the eight full reviewer reports with
`file:line`, repro commands and their scripts.
