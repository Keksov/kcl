# TUtil — the design record, and the TProcess comparison

> **There is no upstream source for this unit.** Every other `docs/*.md` page in
> kcl is a scrape of the FPC/Delphi class being ported, kept so the port can be
> checked against it. `TUtil` has no such page to scrape: **no class is ported
> line by line**. It is a kcl addition, named by the owner (decision D3) after
> the FPC class it is *kin* to — `fcl-process` **`TProcess`** — and sized for
> shell tools instead of for long-running child processes. The normative API and
> contract is **[../README.md](../README.md)**; where this page and the README
> disagree, the README wins.
>
> * **Ported:** nothing, line by line. What `TProcess` and `TUtil` share is the
>   *shape* of the problem — name a program, give it arguments, run it, read its
>   output, read its status — and four members map one to one: `Executable` →
>   `cmd`, `Parameters` → `${inst}_args` / `addArg`, `Execute` → `run`,
>   `ExitStatus` → `lastRc`. [§1](#1-tprocess-member-by-member) is the full
>   member-by-member comparison, including everything that is **wontfix** and
>   why.
> * **Roadmap:** the five wrappers of [§4](#4-the-template-for-the-next-wrappers)
>   — `tsed`, `tawk`, `tfind`, `thead`, `ttail` — one unit each, each with its
>   own PLAN and ledger. Nothing is planned inside `tutil` itself; the surface of
>   [PLAN.md](../PLAN.md) §1.2 is final and a change to it needs an owner
>   decision. `stdinFrom FILE` as a sink option is the one member that was
>   discussed and deferred (PLAN §1.4 item 4).
> * **Wontfix:** the `TProcess` families listed in [§1.2](#12-wontfix-and-why) —
>   the handle/lifecycle model, the Windows console and GUI properties, the
>   environment and working-directory editors, the pipe-stream objects — plus
>   BSD/macOS flag dialects (D4), reading the tool's stderr into `RESULT`, and
>   interactive tools (PLAN §1.4).
> * **Return contract:** a direct call prints nothing and answers in `RESULT`;
>   inside `$( )` the value prints exactly once. **`run` is the one deliberate
>   deviation** — a stream member prints by definition, and its stdout is the
>   tool's, inherited untouched. `each`/`toArray`/`toList`/`count` answer the
>   record count with rc 0, or rc 1 **with the count kept** when the tool exited
>   non-zero (the named deviation inherited from `TPipe`); `first` answers the
>   record, rc 1 only when there was none. A malformed **call** is rc 2,
>   `RESULT=''`, and runs nothing.

**How to read the measurements.** Every script in [§3](#3-the-measurements) can
be pasted into a file and run. Each was run on **bash 5.2.37 (MSYS2 `bash`)** and
on **bash 5.3.9 (`C:/bin/msys64/usr/bin/bash.exe`)**, sequentially, on Windows 11
/ MSYS2 with GNU grep 3.0. Where the output was byte-identical on the two it is
shown once and said so; §3.3 is the one probe whose answer **differs between the
bashes**, and that is the point of it. The scripts were first run during the
critic pass on **2026-09-10** (PLAN §8) and by the implementing workers in P0–P2;
the outputs printed here are the **2026-09-11 re-runs at P3**, against the unit
as shipped.

---

## 1. TProcess, member by member

Source: FPC 3.2.2, `packages/fcl-process/src/process.pp` (the unit, the option
enums and the standalone `RunCommand` family) and `processbody.inc` (the class
body — the declarations below are quoted from it), at the **release_3_2_2** tag.

### 1.1 What maps

| `TProcess` | `TUtil` | Notes |
|---|---|---|
| `Property Executable : TProcessString` | `var cmd` | The one name the wrapper owns. A bash **function** or a **builtin** is as good a `cmd` as an executable, which is what lets a wrapper be a `TPipe` producer without an external process (`tests/002_Sinks.sh` §C). `''` means "not runnable" and every runner answers rc 2 — `TProcess` raises `EProcess` instead. |
| `Property Parameters : TStrings` | `${inst}_args`, `addArg ARG...`, `clearArgs` | A real bash **array**, never a string. `TStrings` splits on assignment and has to be fought with `AddStrings`; here `addArg -e '$(pwd)'` is one word, forever. |
| `Procedure Execute` | `proc run` | `run` is synchronous by definition, so it is `Execute` with `poWaitOnExit` always in `Options`. stdout is **inherited**: the caller's terminal, `$( )`, `<( )` or the left-hand side of a pipe, byte for byte (§3.1). |
| `Function WaitOnExit : Boolean` | — (implied by `run`) | There is no state between "started" and "finished", so there is nothing to wait for. |
| `Property ExitStatus : Integer` | `func lastRc` | The **raw** status, per instance, `-1` until something ran. This is the number that still tells grep's `1` (no match) from its `2` (a real error) apart after `mapRc` has flattened both. |
| `Property ExitCode : Integer` | the member's own rc, via `func mapRc RAW` | FPC's `ExitCode` is the platform's exit code with the signal bits interpreted; kcl's is a three-value contract (0 / 1 / 2, `README.md` §1.2) and `mapRc` is the **virtual** member where a descendant states its tool's rc table. |
| `Property Output : TInputPipeStream` | the five sinks — `each`, `toArray`, `toList`, `first`, `count` | The deep difference. `TProcess` hands you a stream **object** and you write the read loop; `TUtil` hands the argv to [`TPipe`](../../tpipe/README.md), which runs the read loop **in the calling shell**, so a callback that mutates an object keeps every mutation. No handle, no lifecycle, no `ReadInputStream` with a `MaxLoops` parameter. |
| `poUsePipes` in `Options` | implied by every sink | A sink *is* the piped read; `run` *is* the un-piped one. There is no flag to set and no way to get it wrong. |
| `poStderrToOutPut` in `Options` | the caller's `2>&1` | One shell operator, on the call. |
| `function RunCommand(exename; commands; out outputstring; …)` | `TUtil.new u CMD ARG...; u.toArray out` | The nearest functional analogue, and the reason `TUtil` is **concrete**: `TUtil.new u git log --format=%H; u.toArray shas` is the whole `RunCommand` use case with no subclass. FPC's returns the output as **one string**; ours returns **records**, which is almost always what the caller wanted. |
| `function RunCommandIndir(curdir, …)` | `( cd DIR && u.toArray out )` | See `CurrentDirectory` below. |
| `EProcess = Class(Exception)` | rc 2 + one `kk.debug` line | kcl has no exceptions (`README.md` §1.2): a malformed **call** is rc 2 and runs nothing, a failed **run** is rc 1 with the raw status readable. |

### 1.2 Wontfix, and why

| `TProcess` | Why it is not here |
|---|---|
| `Property Handle`, `ProcessHandle`, `ThreadHandle`, `ProcessID`, `ThreadID` | There is no handle model. A `TUtil` call is one foreground command, started and finished inside the member; between two calls there is no process to hold a handle to. |
| `Function Resume`, `Function Suspend`, `Function Terminate(AExitCode)`, `poRunSuspended`, `Property Running`, `Property Active` | The same reason. The one control a caller has over a *running* producer is `TPipe.stop` from inside a callback, which is the consumer saying "enough" — tpipe `README.md` §5, and `TUtil` passes it through untouched (`tests/002_Sinks.sh` §I). |
| `Property Input : TOutputPipeStream`, `CloseInput`, `poPassInput` | Writing to the tool's stdin. Deferred, not refused: PLAN §1.4 item 4 records `stdinFrom FILE` as a possible sink option. Today a caller redirects the call: `printf '%s\n' a b \| u.run`, or `u.run < file`. |
| `Property Stderr : TInputPipeStream`, `CloseStderr`, `poStderrToOutPut` as a property | The tool's stderr **passes through** by design (PLAN §1.4 item 2). Capturing it into `RESULT` would mean a second reader and a second framing decision for bytes that are diagnostics, not data. `2>/dev/null` and `2>&1` are one operator each. |
| `Property CurrentDirectory` | `( cd DIR && u.run )` is one subshell and costs nothing, and most tools take a path operand anyway — which the wrapper already passes safely. Storing a directory on the instance would add a second place for a path to be wrong. |
| `Property Environment : TStrings` | An argv is a `cmd` plus words; `VAR=x cmd` is a shell *assignment prefix*, not a word, so it cannot be an element of `${inst}_argv` without `eval`. A caller who needs it makes the `cmd` a one-line function — the function is then the wrapper's `cmd` and the environment is set inside it. |
| `Property Options : TProcessOptions` and the rest of `TProcessOption` (`poNoConsole`, `poNewConsole`, `poDefaultErrorMode`, `poNewProcessGroup`, `poDebugProcess`, `poDebugOnlyThisProcess`, `poDetached`, `poRunIdle`) | Windows process-creation flags and a debugger attach. Nothing in a bash wrapper can use them. |
| `Property Priority : TProcessPriority` | `nice` is a `cmd`. |
| `Property ShowWindow`, `StartupOptions`, `WindowColumns`, `WindowHeight`, `WindowLeft`, `WindowRows`, `WindowTop`, `WindowWidth`, `WindowRect`, `FillAttribute`, `Desktop`, `ConsoleTitle`, `XTermProgram`, the whole `TShowWindowOptions` and `TStartupOption` sets | GUI and console-host decoration. PLAN §1.4 item 3: interactive tools and anything that needs a tty are out of scope. |
| `Property CommandLine` (deprecated in FPC itself) | A single string that the RTL re-splits. Refusing it **is** the unit's thesis (README §1: "typed options → an argv ARRAY, no string building"). |
| `Property InheritHandles`, `Property PipeBufferSize` | Handle inheritance is the shell's, and the pipe buffer is the OS's. |
| `Property OnRunCommandEvent`, `Property RunCommandSleepTime`, `function RunCommandLoop`, `function ReadInputStream(…MaxLoops)` | The polling read loop `TProcess` needs because it owns the stream. `TPipe` reads with a blocking `read` on a real fd and needs no poll, no sleep and no loop counter. |
| BSD/macOS flag dialects | D4: the wrappers model the **GNU** dialect MSYS2 ships, and the behavioural tests assert the GNU banner before they trust a single flag. |

### 1.3 The two members TProcess does not have

`buildArgv` and `argv NAME` have no `TProcess` counterpart at all, and they are
where the wrapper's value is:

* **`buildArgv`** is the single truth about what will run, it is **virtual**, and
  every sink and `run` call it first. A descendant's override is what runs, which
  is why `TGrep` gets `run` and all five sinks for free (README §5).
* **`argv NAME`** builds the command line and **runs nothing**. That is how a
  wrapper's whole option set is pinned by comparing an array instead of executing
  a tool: `tgrep/tests/004_Argv.sh` pins 73 cases of GNU grep's surface without
  starting grep once, and it is the fast half of every wrapper's suite
  ([§4](#4-the-template-for-the-next-wrappers)).

---

## 2. The critic pass — 23 findings and where each landed

An Opus critic reviewed the first draft of the design against the live tree on
**2026-09-10** with 23 probe scripts on both bashes, before a line of `tutil.sh`
existed. Five findings were blockers: each one would have shipped a wrapper that
looked right and was silently wrong. The table is the same numbering as PLAN §8;
the column that matters is the last one — **every one of them is a test today**.

| # | sev | finding | landed in | pinned by |
|---|---|---|---|---|
| C1 | BLOCKER | `$this.func` inside a member prints the callee's `kk._return` under `$( )` / `\|` / `<( )` — `run` leaked digits into its own stream | PLAN §2.2, §6; `kk.call_silent` everywhere in both units | 001 §D (three positions, byte-exact), 006 §0 ("no internal call is spelled `$this.`"); measured in [§3.1](#31-c1--thisfunc-prints-under--) |
| C2 | BLOCKER | `inherited` in a **constructor** is rewritten to `parent.constructor "$@"` and forwards the descendant's arguments — every TGrep path was emitted twice | PLAN §2.1, §6; `TGrep.Create` calls `parent.constructor grep` explicitly | 004 §A (`${g}_args` empty after `new g PAT PATH`), 006 §0 (the source itself); [§3.2](#32-c2--inherited-in-a-constructor-forwards-) |
| C3 | BLOCKER | an unassigned `var` is an **unbound variable** under `set -u`, and `.new` over a still-live instance does not clear `${inst}_data` | PLAN §2.1, §6; both constructors assign **every** declared var | 001 §A (all four vars + `set -u` read), 004 §A (all 23 vars, and a reused name starting clean); [§3.3](#33-c3--an-unassigned-var-is-unbound-under-set--u--and-the-two-bashes-disagree) |
| C4 | BLOCKER | G8 and the flagship example contradicted each other: `grep DIR` without `-r` is rc 2 with zero records | PLAN §2.5 — `search` implies `-r` **and** requires ≥ 1 path; an instance never implies it | 005 §D (7 cases) |
| C5 | BLOCKER | a `func` cannot answer a value **and** a non-zero rc with `RESULT=V; return N` | PLAN §2.3 ordered tail, §6; all four func sinks end `kk._return V; return N` | 002 §B (direct, under `$( )`, on the LHS of a pipe); [§3.4](#34-c5--resultv-return-n-loses-v) |
| C6 | MAJOR | `(` is a **literal** under BRE, so the draft's G6 was wrong without `-E` | PLAN §3 G6 rewritten | 005 §B (4 cases: `-E` + `(`, the literal without it, `-F`, and a valid ERE) |
| C7 | MAJOR | plain `ln -s` produces a **directory copy** on this box, which `-r` then descends for the wrong reason | PLAN §4; fixtures use `kt_make_symlink` (the tdirectory helper, `winsymlinks:native`) | 005 §H (3 cases, `-R` as the counter-oracle) |
| C8 | MAJOR | GNU grep/sed/gawk open input in **text mode** and strip the CR themselves, so `crlf` is a no-op for them; `-U` was missing | PLAN §2.6; the `binary` var | 005 §I (3 cases), the CRLF table in both READMEs |
| C9 | MAJOR | a test file's own `trap … EXIT` **replaces** ktests' trap, which prints the `__COUNTS__` line the runner parses | PLAN §4, §6 | no test file in either unit installs one; fixtures go through `kt_fixture_tmpdir_create` |
| C10 | MAJOR | `-Z` is NUL **termination** only together with `-l`/`-L`; a plain `var` cannot set another var | PLAN §2.7; the derived `-0` and the private `_nulDerived` | 004 §G (9 cases), 005 §C (4 cases); [§3.8](#38-27--the--0-derivation-and-the-shape-it-used-to-get-wrong) — including **P3-F1**, found and fixed at P3 |
| C11 | MAJOR | grep answers **2 while still delivering matches**, and `Binary file X matches` is a **stdout record** | PLAN §2.4, §1.4 item 7 | 005 §F (3 cases), §K (3 cases); the named deviation in the kcl README §2 row |
| C12 | MAJOR | a bare `"${argv[@]}"` inside a member aborts a `set -e` caller before `_lastRc` is stored | PLAN §2.3, §6; `run` is `"${__tu_v[@]}" \|\| __tu_rc=$?` | 001 §F, 003 §1 (17 children under `set -eu`) |
| C13 | MAJOR | a **fixed** throw-away instance name is deleted out from under an outer `search` by a nested one | PLAN §2.5; `__tg_s_${BASHPID}_${__TG_SEQ}` | 005 §G (2 nesting shapes), §D (the seq bump) |
| C14 | MAJOR | no binary was pinned, and a **non-GNU grep** (Embarcadero) is on PATH on this box | the unit header, PLAN §4 | the GNU banner gate is case 1 of 005, 006 and 007 |
| C15 | MAJOR | a missing `cmd` makes **bash** print its own `command not found`, unconditionally and attributed to `kklass.sh` | PLAN §2.3; the `command -v -- "$cmd"` pre-check in `run` and in `tutil._prep` | 001 §D (silent without the switch, exactly one line with it), 002 §J, 003 §3; [§3.5](#35-c15--the-command-not-found-line-comes-from-bash-not-from-us) |
| C16 | MINOR | a `var` and an inherited **method** of the same name: the method wrapper is generated last and wins silently | PLAN §1.2 reserved names; both READMEs §4 / §8 | 006 §0 ("no `var` shadows a TUtil or kklass member name") |
| C17 | MINOR | `kk.isInt` accepts a negative, grep reads `-m -1` as *no limit* silently, and the OUTVAR form writes through the property nameref | PLAN §1.3, §6; `$__KK_INT` + a separate `>= 0` check | 004 §F (8 cases: `abc`, `-1`, `'1 2'`, `0x10` refused; `0`, `08`→8, `+5`→5 accepted without a write-back) |
| C18 | MINOR | grep **accepts** `-h -H` and `-l -L` with order-dependent results | PLAN §1.3 rc 2 list | 004 §E (5 refusals + "each half on its own is fine") |
| C19 | MINOR | an empty pattern matches every line, and the draft had no decision | PLAN §1.3 — rc 2 | 004 §E, 006 §1 |
| C20 | MINOR | sed's `--` asymmetry was unexplained | PLAN §7, restated in [§4](#4-the-template-for-the-next-wrappers) | — (documentation; the tsed unit's own tests will pin it) |
| C21 | MINOR | `TStringList.Add` may answer rc 1 under `dupError`, so a `toList` count is "records **offered**" | tpipe PLAN §2.4; README §3 | 002 §G (THashSet duplicates: 5 offered, 3 kept), 003 §1 |
| C22 | NIT | the `TQueueStack` out-name helper answers rc 1 and its caller converts | PLAN §2.1; `tutil._badOut` keeps the shape, the **caller** converts to rc 2 | 001 §C (11 refusals) |
| C23 | NIT | a `func` **stub** that does not call `kk._return` cannot be asserted | PLAN §5 P0.1; the P0 stubs answered `__TUTIL_PENDING__` | 001 §G (the sentinel is gone from every member **and** from the source) |

Eighteen further claims the critic checked and found **correct** are listed in
PLAN §8 and were not re-probed: the thin static dispatcher survives a static +
variadic constructor + instance members with no static vars; `--format=%H`
reaches `Create` verbatim; base→override virtual dispatch works across files; the
destructor `inherited` chain frees everything; `declare -g -a` + a nameref reset
+ `unset`; `TGrep.search` as a `<( )` / `|` producer is clean; `-e` with a
leading-`-` pattern; `-Z -l` with a newline in a name; `-z`; `--include` with
`-r`; `-m 8` and `-m8`; `-F` + `-E` is grep rc 2; `-r` vs `-R` on a real symlink;
`RESULT=-1` has corpus precedent (tarray, tlist); and the kcl README §2 row is the
house mechanism for naming a deviation.

---

## 3. The measurements

Eight probes. Each is the script, then its output. Six are byte-identical on the
two bashes; §3.3 is not, and §3.6 records a shape that is still wrong.

### 3.1 C1 — `$this.func` prints under `$( )`

`$this.NAME` compiles to `$__inst__.call NAME`, which does **not** set
`__kk_return_silent`. The callee's `kk._return` then writes its value to stdout
whenever the outer member is running in a subshell — which is exactly the three
positions `run` exists for. `kk.call_silent` sets and restores the flag, keeps
`RESULT`, and still dispatches **virtually**.

```bash
#!/bin/bash
source /c/projects/kkbot/kbool/kklass/kklass_pascal.sh

class TStream
    public
        constructor Create
        func pre
        func post
        proc runThis          # internal calls spelled `$this.NAME`
        proc runSilent        # the same body, `kk.call_silent`
end
TStream.Create()    { return 0; }
TStream.pre()       { kk._return "2"; return 0; }
TStream.post()      { kk._return "0"; return 0; }
TStream.runThis()   { $this.pre; printf 'A\nB\n'; $this.post; return 0; }
TStream.runSilent() {
    kk.call_silent "$__inst__" pre
    printf 'A\nB\n'
    kk.call_silent "$__inst__" post
    return 0
}
build TStream

TStream.new v
printf '$this.NAME,     direct call:   '; v.runThis
printf '$this.NAME,     od -c < <( ):  '; od -c < <( v.runThis ) | head -1
printf '$this.NAME,     "$( )":        '; printf '%q\n' "$( v.runThis )"
printf 'kk.call_silent, direct call:   '; v.runSilent
printf 'kk.call_silent, od -c < <( ):  '; od -c < <( v.runSilent ) | head -1
printf 'kk.call_silent, "$( )":        '; printf '%q\n' "$( v.runSilent )"
v.delete
```

Identical on 5.2.37 and 5.3.9:

```
$this.NAME,     direct call:   A
B
$this.NAME,     od -c < <( ):  0000000   2   A  \n   B  \n   0
$this.NAME,     "$( )":        $'2A\nB\n0'
kk.call_silent, direct call:   A
B
kk.call_silent, od -c < <( ):  0000000   A  \n   B  \n
kk.call_silent, "$( )":        $'A\nB'
```

The direct call looks fine in both spellings — that is what makes it a blocker.
`buildArgv`'s word count (`2`) and `mapRc`'s value (`0`) wrapped themselves around
the tool's own bytes the moment anyone captured the stream. `tests/001_Core.sh`
§D pins `$(u.run)`, `od -c < <(u.run)` and `u.run | od -c` byte-identical to the
bare tool, including a producer that emits `-n`, a backslash, a glob, a CR and an
unterminated tail.

### 3.2 C2 — `inherited` in a constructor forwards `"$@"`

The Pascal front-end rewrites both `inherited` and `inherited Create` in a
constructor body into `parent.constructor "$@"`, forwarding the **descendant's**
arguments unchanged. For `TGrep.Create PATTERN PATH...` that hands `TUtil`
`cmd = PATTERN` and every path as a TUtil extra arg — so every path lands in the
built argv twice, once from `${inst}_args` and once from `${inst}_paths`.

```bash
#!/bin/bash
source /c/projects/kkbot/kbool/kklass/kklass_pascal.sh

class TB
    public
        var cmd
        constructor Create
end
TB.Create() {
    cmd="${1:-}"
    declare -ga "${__inst__}_args=()"
    local -n a="${__inst__}_args"; a=( "${@:2}" )
    return 0
}
build TB

class TDInherited : TB
    public
        var pattern
        constructor Create
end
TDInherited.Create() {
    inherited                       # <- the trap
    pattern="${1:-}"
    declare -ga "${__inst__}_paths=()"
    local -n p="${__inst__}_paths"; p=( "${@:2}" )
    return 0
}
build TDInherited

class TDExplicit : TB
    public
        var pattern
        constructor Create
end
TDExplicit.Create() {
    parent.constructor grep         # <- the fix
    pattern="${1:-}"
    declare -ga "${__inst__}_paths=()"
    local -n p="${__inst__}_paths"; p=( "${@:2}" )
    return 0
}
build TDExplicit

TDInherited.new g needle src/ doc/
printf '`inherited`:          cmd=%s  args=(%s)  paths=(%s)\n' \
    "$( g.cmd )" "${g_args[*]}" "${g_paths[*]}"
TDExplicit.new h needle src/ doc/
printf '`parent.constructor`: cmd=%s  args=(%s)  paths=(%s)\n' \
    "$( h.cmd )" "${h_args[*]}" "${h_paths[*]}"
g.delete; h.delete
```

Identical on 5.2.37 and 5.3.9:

```
`inherited`:          cmd=needle  args=(src/ doc/)  paths=(src/ doc/)
`parent.constructor`: cmd=grep  args=()  paths=(src/ doc/)
```

`cmd` became the **pattern** and the paths are in both arrays. In a *destructor*
`inherited` is the ordinary parent call and is exactly right — `TGrep.Destroy`
frees `${inst}_paths` and then chains (`tests/004_Argv.sh` §A pins that `delete`
removes all three arrays).

### 3.3 C3 — an unassigned `var` is unbound under `set -u`, **and the two bashes disagree**

kklass binds a property as a nameref onto `${inst}_data[NAME]`. If the
constructor never assigned it, the key does not exist, and reading the nameref
under `set -u` is an unbound-variable error — on **5.3.9**. On **5.2.37** the
same read is silently empty. That difference is the strongest argument for the
rule: a unit that assigns every var cannot be bitten by either behaviour, and a
unit that does not will pass its suite on one bash and die on the other.

```bash
#!/bin/bash
source /c/projects/kkbot/kbool/kklass/kklass_pascal.sh

class TV
    public
        var assigned
        var forgotten
        constructor Create
        func readForgotten
end
TV.Create()        { assigned="${1:-}"; return 0; }   # `forgotten` is never set
TV.readForgotten() { kk._return "[$forgotten]"; return 0; }
build TV

TV.new a first
set -u
if out="$( a.readForgotten 2>&1 )"; then
    printf 'unassigned var under set -u: rc 0, RESULT %q\n' "$out"
else
    printf 'unassigned var under set -u: rc %s, stderr %q\n' "$?" "$out"
fi
set +u

a.forgotten = LEFTOVER
TV.new a second                       # .new over a LIVE instance
a.readForgotten
printf 'after a second `TV.new a`:   RESULT %q\n' "$RESULT"
a.delete
```

bash **5.2.37**:

```
unassigned var under set -u: rc 0, RESULT \[\]
after a second `TV.new a`:   RESULT \[LEFTOVER\]
```

bash **5.3.9**:

```
unassigned var under set -u: rc 1, stderr /c/projects/kkbot/kbool/kklass/kklass.sh:\ line\ 375:\ forgotten:\ unbound\ variable
after a second `TV.new a`:   RESULT \[LEFTOVER\]
```

The second line is the same on both and is the other half of the finding:
**`.new` over a still-live instance does not clear `${inst}_data`**, so an
unassigned var can also inherit the *previous* instance's value. `TUtil.Create`
assigns four vars and `TGrep.Create` assigns twenty-three, no exception;
`tests/001_Core.sh` §A and `tgrep/tests/004_Argv.sh` §A assert that
`declare -p ${inst}_data` lists every one of them right after `new`, with its
documented default, and that a reused instance name starts clean.

### 3.4 C5 — `RESULT=V; return N` loses V

`build` compiles a `kk._return "$RESULT"` trailer onto every `func` body. An
explicit `return` **skips** it, and `kk._invoke` then restores the **caller's**
`RESULT`. A sink has to answer both a count and a mapped rc, so this is the one
spelling that works.

```bash
#!/bin/bash
source /c/projects/kkbot/kbool/kklass/kklass_pascal.sh

class TR
    public
        constructor Create
        func bare          # RESULT=3; return 1
        func ordered       # kk._return 3; return 1
end
TR.Create()  { return 0; }
TR.bare()    { RESULT=3; return 1; }
TR.ordered() { kk._return 3; return 1; }
build TR

TR.new r
RESULT='the caller had this'; r.bare;    printf 'RESULT=3; return 1     -> rc %s, RESULT %q\n' "$?" "$RESULT"
RESULT='the caller had this'; r.ordered; printf 'kk._return 3; return 1 -> rc %s, RESULT %q\n' "$?" "$RESULT"
r.delete
```

Identical on 5.2.37 and 5.3.9:

```
RESULT=3; return 1     -> rc 1, RESULT the\ caller\ had\ this
kk._return 3; return 1 -> rc 1, RESULT 3
```

Note what the first line does **not** say: there is no error, no empty value, no
diagnostic. The caller gets its own previous `RESULT` back and every rc is
correct, so a test that checks only the rc passes. `tests/002_Sinks.sh` §B checks
the value as well, in three positions, for all four func sinks.

### 3.5 C15 — the `command not found` line comes from **bash**, not from us

kcl `README.md` §1.2: nothing reaches stderr unless `VERBOSE_KKLASS=debug` is
set. bash's own diagnostic for a missing command ignores that entirely, and
because a member body is re-created from `declare -f` through `eval`, it is
attributed to `kklass.sh` and a line number inside kklass — which sends the
reader to the wrong file.

```bash
#!/bin/bash
source /c/projects/kkbot/kbool/kklass/kklass_pascal.sh

class TN
    public
        var cmd
        constructor Create
        proc runRaw        # no pre-check
        proc runChecked    # the TUtil shape
end
TN.Create()     { cmd="${1:-}"; return 0; }
TN.runRaw()     { local rc=0; "$cmd" || rc=$?; return 0; }
TN.runChecked() {
    if ! command -v -- "$cmd" >/dev/null 2>&1; then
        kk.debug "Error: TN.runChecked: command not found: '$cmd'"
        return 1
    fi
    local rc=0; "$cmd" || rc=$?; return 0
}
build TN

printf 'VERBOSE_KKLASS is %q (the switch is OFF)\n' "${VERBOSE_KKLASS:-}"
TN.new n no_such_tool_xyz
printf 'no pre-check, stderr: '; n.runRaw     2>&1 >/dev/null | head -1
printf 'pre-check,    stderr: '; n.runChecked 2>&1 >/dev/null | head -1; printf '(empty)\n'
n.delete
```

Identical on 5.2.37 and 5.3.9:

```
VERBOSE_KKLASS is '' (the switch is OFF)
no pre-check, stderr: /c/projects/kkbot/kbool/kklass/kklass.sh: line 376: no_such_tool_xyz: command not found
pre-check,    stderr: (empty)
```

`command -v` is a **builtin**: the pre-check costs no fork. `run` and all five
sinks do it (`tutil._prep` step 2), answer rc 1 with `lastRc = 127` and one
`kk.debug` line, and **nothing runs**. This is deliberately stricter than
`TPipe`, which takes an arbitrary argv and cannot know the command; `TUtil` owns
`cmd`, so it can check it.

### 3.6 P1-F1 — `__TPIPE_QUIET`, and why a redirect is not the fix

`tpipe._ret` prints TPipe's `RESULT` whenever `BASH_SUBSHELL > 0`. That is right
for a caller that **is** the answer and wrong for one that **composes**: a sink
answering through its own `kk._return` printed the same value a second time.
`kk.call_silent` cannot help — `tpipe._ret` does not read `__kk_return_silent`,
and kklass's thin static dispatcher sets that flag to 1 for every static body
anyway. So TPipe carries a dedicated, dynamically scoped opt-out (tpipe
`README.md` §7) and all five `TUtil` sinks declare `local __TPIPE_QUIET=1`.

The first attempted fix was `>/dev/null` on the delegated call. It suppresses the
count — and the callback's own output, and a printing `.Add`'s, with it.

```bash
#!/bin/bash
source /c/projects/kkbot/kbool/kcl/tutil/tutil.sh

p2()  { printf 'x\ny\n'; }
pcb() { printf 'cb:%s\n' "$1"; return 0; }

noquiet_count() { TPipe.count -- p2; kk._return "$RESULT"; return 0; }
quiet_count()   { local __TPIPE_QUIET=1; TPipe.count -- p2; kk._return "$RESULT"; return 0; }
redirect_each() { TPipe.each pcb -- p2 >/dev/null; return 0; }

printf 'TPipe.count direct, $( ):        %q\n' "$( TPipe.count -- p2 )"
printf 'no seam,    $(wrapper):          %q\n' "$( noquiet_count )"
printf 'with seam,  $(wrapper):          %q\n' "$( quiet_count )"

TUtil.new u p2
printf 'the shipped sink, $(u.count):    %q\n' "$( u.count )"
printf 'the shipped sink, u.each cb|cat: %q\n' "$( u.each pcb | cat )"
printf 'the redirect "fix", $( ):        %q\n' "$( redirect_each )"
u.delete
```

Identical on 5.2.37 and 5.3.9:

```
TPipe.count direct, $( ):        2
no seam,    $(wrapper):          22
with seam,  $(wrapper):          2
the shipped sink, $(u.count):    2
the shipped sink, u.each cb|cat: $'cb:x\ncb:y'
the redirect "fix", $( ):        ''
```

`22` is two records printed twice, not twenty-two — which is exactly how a bug
like this survives a review. The last line is the redirect: the callback's own
`cb:x` / `cb:y` are gone with it. One consequence of dynamic scoping: a
**callback** invoked by a sink also sees the `1`, so a callback that itself
captures a sink (`x=$(TPipe.count -- …)`) must declare `local __TPIPE_QUIET=0`
first. Pinned by `tests/002_Sinks.sh` §B (7 cases) and tpipe's own 004.

### 3.7 P1-F2 — a CR does not survive an array compound assignment

Not kklass's, not this unit's — bash on this platform. It bites **tests**, not
member bodies, and it is why every CR-bearing expected value in both suites is
built with `printf -v CR '\r'` and copied with a plain `COPY=( "${SRC[@]}" )`.

```bash
#!/bin/bash
printf -v CR '\r'
x=$'cr\r';                  printf "x=\$'cr\\\\r'          len %s\n" "${#x}"
A=( $'cr\r' );              printf "A=( \$'cr\\\\r' )      len %s\n" "${#A[0]}"
B=( $'a\rb' );              printf "B=( \$'a\\\\rb' )      len %s  (%q)\n" "${#B[0]}" "${B[0]}"
S=( "cr\$CR" );             printf 'S=( "cr$CR" )       len %s\n' "${#S[0]}"
C=( "${S[@]}" );            printf 'C=( "${S[@]}" )     len %s\n' "${#C[0]}"
declare -a D=( "${S[@]}" ); printf 'declare -a D=( … )  len %s\n' "${#D[0]}"
T=$'tab\t'; TA=( $'tab\t' );printf 'the same with a TAB: scalar %s, array %s\n' "${#T}" "${#TA[0]}"
printf 'shopt igncr exists? '; shopt -p igncr >/dev/null 2>&1 && echo yes || echo no
```

Identical on 5.2.37 and 5.3.9 (the `S=` line needs the CR to come from the
variable, unescaped, when you paste it):

```
x=$'cr\r'          len 3
A=( $'cr\r' )      len 2
B=( $'a\rb' )      len 2  (ab)
S=( "cr$CR" )      len 3
C=( "${S[@]}" )    len 3
declare -a D=( … ) len 2
the same with a TAB: scalar 4, array 4
shopt igncr exists? no
```

A plain assignment keeps the CR; a **word of a compound array assignment** drops
it; `declare -a` re-parses and drops it even out of a quoted expansion; TAB, NL
and a backslash are unaffected, and `shopt igncr` does not exist here. It is the
same "a raw CR does not survive a second parse" class as the kklass `build` trap
(a literal `$'\r'` written inside a member body does not survive the
`declare -f` → `eval` round trip — tpipe `README.md` §7), which both units' 003 /
006 grep for in the source.

### 3.8 §2.7 — the `-0` derivation, and the shape it used to get wrong

`-Z` is NUL **termination** only together with `-l`/`-L`. With `-c`, and with
normal output, it merely replaces the separator after the file name and the
record still ends in `\n`:

```bash
printf 'needle a\nneedle b\n' > a.txt; printf 'needle c\n' > b.txt; printf 'zzz\n' > c.txt
for f in "-l -Z" "-L -Z" "-c -Z" "-Z"; do
    printf '%-8s : ' "$f"; grep $f -e needle -- a.txt b.txt c.txt | od -c | head -2
done
```

GNU grep 3.0, identical under both bashes:

```
-l -Z    : 0000000   a   .   t   x   t  \0   b   .   t   x   t  \0
-L -Z    : 0000000   c   .   t   x   t  \0
-c -Z    : 0000000   a   .   t   x   t  \0   2  \n   b   .   t   x   t  \0   1  \n
           0000020   c   .   t   x   t  \0   0  \n
-Z       : 0000000   a   .   t   x   t  \0   n   e   e   d   l   e       a  \n
           0000020   a   .   t   x   t  \0   n   e   e   d   l   e       b  \n
```

Handing the last two to the sinks' `-0` would mis-frame every record, so
`buildArgv` **derives** the framing: `nullOut == 1` **and** (`filesOnly == 1`
**or** `filesWithoutMatch == 1`) → `nul = 1`. The P2 worker found that a
*set-only* rule was not idempotent — turning `filesOnly` back off left the sinks
framing on NUL — and added the private `_nulDerived` var to record who set it.

**P3-F1 — found at P3 while writing this page, fixed in the same phase.** The
undo was one condition too coarse. `_nulDerived` was set whenever the derivation
*condition* held, even when `nul` was **already 1 because the caller set it**;
the next build that stopped deriving then took the caller's own `nul` down to 0
with it. The bookkeeping has to distinguish **three** states — derived (ours,
undo it), caller-set (never touch), off — and it was only distinguishing two.
This is the probe that found it:

```bash
#!/bin/bash
source /c/projects/kkbot/kbool/kcl/tgrep/tgrep.sh
show() { printf '%-42s nul=%s _nulDerived=%s\n' "$1" "$( g.nul )" "$( g._nulDerived )"; }

TGrep.new g needle .
g.nullOut = 1;   g.buildArgv >/dev/null; show "nullOut=1 alone (-Z, normal output)"
g.filesOnly = 1; g.buildArgv >/dev/null; show "nullOut=1 + filesOnly=1 (-lZ)"
g.filesOnly = 0; g.buildArgv >/dev/null; show "filesOnly back to 0"
g.delete

TGrep.new g needle .
g.nul = 1                                   # the CALLER's own decision
g.buildArgv >/dev/null; show "caller set nul=1, no -Z"
g.nullOut = 1; g.filesOnly = 1
g.buildArgv >/dev/null; show "...then -lZ"
g.filesOnly = 0
g.buildArgv >/dev/null; show "...then filesOnly off"
g.delete
```

**Before the fix**, identical on 5.2.37 and 5.3.9:

```
nullOut=1 alone (-Z, normal output)        nul=0 _nulDerived=0
nullOut=1 + filesOnly=1 (-lZ)              nul=1 _nulDerived=1
filesOnly back to 0                        nul=0 _nulDerived=0     <- correct
caller set nul=1, no -Z                    nul=1 _nulDerived=0
...then -lZ                                nul=1 _nulDerived=1     <- claimed, wrongly
...then filesOnly off                      nul=0 _nulDerived=0     <- WRONG
```

The first block is the shape the unit was written for and it was always right.
The second was the bug: the caller asked for `nul = 1`, the derivation never
actually changed anything (it was already 1), and the undo took it away anyway.
The fix is one guard — claim ownership only when the derivation really sets the
value:

```bash
if [[ "$nullOut" == 1 ]] && [[ "$filesOnly" == 1 || "$filesWithoutMatch" == 1 ]]; then
    if [[ "$nul" != 1 ]]; then nul=1; _nulDerived=1; fi      # <- the guard
elif [[ "$_nulDerived" == 1 ]]; then
    nul=0; _nulDerived=0
fi
```

**After the fix**, identical on both bashes — the first block is unchanged and
the second now keeps what the caller asked for:

```
nullOut=1 alone (-Z, normal output)        nul=0 _nulDerived=0
nullOut=1 + filesOnly=1 (-lZ)              nul=1 _nulDerived=1
filesOnly back to 0                        nul=0 _nulDerived=0
caller set nul=1, no -Z                    nul=1 _nulDerived=0
...then -lZ                                nul=1 _nulDerived=0
...then filesOnly off                      nul=1 _nulDerived=0
```

`tgrep/tests/004_Argv.sh` §G pins the whole sequence (red-first: 1 FAIL of 184
against the unguarded code, with the failure message printing exactly the
`nul=0` above) alongside the six shapes that were always right.

---

## 4. The template for the next wrappers

Each of these is its own unit (`kcl/tsed/`, `kcl/tawk/`, …) with its own PLAN and
ledger, and each follows the `TGrep` shape: **argv pins first** (fast, no tool
run), then the fixture suite behind a GNU-banner gate, then the contract file.
The version notes were verified on the installed tools on **2026-09-10** and
re-checked at P3.

| unit | tool | typed options (first wave) | rc map | notes |
|---|---|---|---|---|
| `tsed` | GNU sed 4.9 | `expr` (`-e`, repeatable via `addArg`), `inPlace` (`-i`; **refused by the sinks**, `run` only), `extended` (`-E`), `quiet` (`-n`), `nullData` (`-z`) | 0→0; 1 (bad command)→1+debug; 2 (missing file)→1+debug; 4 (I/O)→1+debug | `-e` always first; `--` before paths; strips the CR in text mode like grep |
| `tawk` | gawk 5.0 (msys) / 5.4 (cygwin) | `program` (via `-e`) / `programFile` (`-f`), `fieldSep` (`-F`), `assign` (`-v`, repeatable) | 0→0; else →1+debug | the program text is **data**; text-mode CR strip |
| `tfind` | findutils 4.10 | `name`, `iname`, `type`, `maxDepth`, `minDepth`, `newer`, `print0` (→ derived `-0`) | 0→0; 1→1+debug | options (`-maxdepth`) before tests by convention; `-print0` last |
| `thead` / `ttail` | coreutils 8.32 | `lines` (`-n`), `bytes` (`-c`), `follow` (tail `-f`, **sinks refuse**, `run` only), `zeroTerminated` (`-z`) | 0→0; 1→1+debug | the `-n` value through `kk.isInt`; these **keep** the CR — `crlf` matters here |

Verified on the installed versions: `sed -e EXPR -- FILE` works, and so does
`-- -weird.txt`; `gawk -e PROG FILE` works on 5.0 and on 5.4; `head -n 1 -- FILE`
works; findutils 4.10 accepts `-name X -maxdepth 1` without a warning.

**The `--` asymmetry (C20).** `--` is *not* a full option terminator for sed's
expression slot: `sed -- -e 's/a/b/' f` is an error, because after `--` the `-e`
is an operand and sed takes it as the *script*. That is why every wrapper in this
family emits its expression flags **first**, then `--`, then paths — the same
order `TGrep.buildArgv` uses for `-e PATTERN`.

**Reserved member names.** `TUtil` owns `cmd crlf nul _lastRc buildArgv addArg
clearArgs argv run each toArray toList first count lastRc mapRc` and kklass owns
`property call parent delete`. A descendant must not declare a `var` with any of
them: the method wrapper is generated after the property wrapper and wins
silently, so `obj.count = 5` would be accepted and discarded (C16). That is why
`thead`/`ttail` use `lines` and `bytes`, never `count` or `first`.

**The two members that must be overridden, and the two that must not be
touched.** A wrapper overrides `buildArgv` (always) and `mapRc` (almost always),
and inherits `run` and the five sinks unchanged — they reach the overrides
through `kk.call_silent`, which dispatches **virtually**. There is nothing else
to re-implement, and re-implementing a sink would mean re-deriving the ordered
tail of PLAN §2.3 from scratch.
