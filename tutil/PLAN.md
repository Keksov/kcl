# TUtil — CLI-tool wrapper base, and TGrep, the first wrapper (kcl/tutil, kcl/tgrep)

**P4 (D6 final: `var subshellOk`, owner ruling 2026-09-15) PLANNED — see §5 P4; runs in the same worker cycle as tpipe P3.**

**Status: COMPLETE (P0–P3), 2026-09-11.** Both units shipped:
`kcl/tutil` (`TUtil`, **172/172** on bash 5.2.37 and on 5.3.9) and `kcl/tgrep`
(`TGrep : TUtil`, **184/184** on both), threaded and under `--mode single`; both
benches rc 0 under `bash -eu` with every gate PASS. One code fix landed in the
closeout, **P3-F1** — see the P3 note in §5. Phase history and every
measured number: `tutil_ledger.json`; the design record and the `TProcess`
comparison: `tutil/docs/TUtil.md`.

Originally **PLANNED, critic-hardened (2026-09-10)**: owner accepted the
design and the defaults D1–D5 in `kcl/tpipe/PLAN.md` §2.0. A critic pass (§8)
found 5 blockers and 10 majors in the first draft; every one is folded into the
sections below, so the worker reads the sections, not §8.

**Roadmap position:** owner request 2026-09-10; depends on `tpipe` (all sinks
delegate to it). Order: tpipe → tutil (this file, P0–P1) → tgrep (this file, P2) →
closeout (P3) → the next wrappers, one unit each, from the §7 template.
**Source of truth:** no FPC class is ported line by line. The base is modelled on
FPC `fcl-process` **`TProcess`** (`Executable`, `Parameters`, `Execute`,
`ExitStatus`) in spirit, and named `TUtil` by the owner (D3). The wrappers are
modelled on the **GNU** tools MSYS2 ships (D4): grep 3.0, sed 4.9, gawk 5.0 (msys)
/ 5.4 (cygwin), findutils 4.10, coreutils 8.32. D4 fixes the *dialect*, not the
binary: `cmd` is a bare name resolved by PATH, and the behavioural tests first
assert the GNU banner (§4).
**Targets:** `kcl/tutil/tutil.sh` — kklass Pascal-DSL **instance** class `TUtil`
(concrete: a generic argv runner); `kcl/tgrep/tgrep.sh` — `TGrep : TUtil` (sources
`../tutil/tutil.sh` by `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`, the
tobjectlist→tlist pattern, verified across files by the critic).
**Ledger:** `kcl/tutil/tutil_ledger.json` (one ledger for both units; tgrep gets its
own when the second wrapper lands and the template in §7 is exercised).
**Workflow / conventions:** as `kcl/tpipe/PLAN.md`. Local prefix `__tu_` (tutil),
`__tg_` (tgrep). No `static var` anywhere (thin dispatcher).

---

## 1. Scoping analysis

### 1.1 What a wrapper buys over calling the tool

1. **Typed options → argv, no string building.** `g.ignoreCase = 1; g.paths "a b"`
   becomes `grep -i -e PATTERN -- 'a b'`. No `eval`, no word splitting, a path with
   a space or a pattern starting with `-` is safe by construction.
2. **One rc convention.** grep's 0/1/2, sed's 0/1/2/4, find's 0/1 all map onto kcl
   §1.2: rc 0, silent rc 1, `kk.debug` on a tool *error*; the raw rc stays readable.
3. **The sinks.** `run` (stream), `each`, `toArray`, `toList`, `first`, `count` on
   every wrapper, all through `TPipe`, so a wrapper is a producer that composes with
   real pipes **and** with the safe `--` form.
4. **A place for platform notes** (CRLF and text-mode tools, MSYS path quirks,
   GNU-only flags) that otherwise live in every script that calls the tool.

### 1.2 Surface — TUtil

```bash
class TUtil
    public
        var  cmd            # executable / function / builtin name; '' = not runnable
        var  crlf           # 1 → sinks strip one trailing \r per record (TPipe -c)
        var  nul            # 1 → records are NUL-terminated (TPipe -0)
        var  _lastRc        # raw rc of the last run/sink; -1 until one ran
        var  subshellOk     # 1 → every sink passes -s to TPipe (D6 final Q9); default 0
        constructor Create  # [CMD [ARG...]] — cmd + initial extra args; assigns EVERY var
        destructor  Destroy # frees ${inst}_args and ${inst}_argv (§1.9)
        func buildArgv      # virtual by kklass default; fills ${inst}_argv; RESULT = count. Base: cmd + args
        proc addArg         # ARG... appended to ${inst}_args (escape hatch for un-modelled options)
        proc clearArgs
        func argv           # NAME — buildArgv, then copy into caller array; RESULT = count; runs nothing
        proc run            # "${argv[@]}" in the foreground, stdout inherited; rc = mapRc
        proc each           # CB       → TPipe.each  [-0] [-c] CB   -- "${argv[@]}"
        func toArray        # NAME     → TPipe.toArray             NAME -- …
        func toList         # INST     → TPipe.toList              INST -- …
        func first          #          → TPipe.first                    -- …
        func count          #          → TPipe.count                    -- …
        func lastRc         # RESULT = _lastRc
        func mapRc          # virtual; RAW → RESULT = normalised rc (base: 0→0, 127→1 + debug, else 1 silent)
end
```

`TUtil` is **concrete**: `TUtil.new u git log --format=%H; u.each r.onLine` is the
whole TProcess use case with no subclass (constructor arguments after the instance
name reach `Create` verbatim, `--format=%H` included — verified). A descendant adds
typed properties and overrides `buildArgv` (and usually `mapRc`).

**Reserved member names.** `TUtil` owns `cmd crlf nul _lastRc subshellOk buildArgv
addArg clearArgs argv run each toArray toList first count lastRc mapRc`; kklass owns
`property call parent delete` on every instance. A descendant must **not** declare
a `var` with any of these names: the method wrapper is generated after the property
wrapper and wins silently (`kklass.sh:911`), so `obj.count = 5` would be accepted
and discarded. The §7 wrappers use `lines`/`bytes`, never `count`/`first`.

### 1.3 Surface — TGrep

```bash
class TGrep : TUtil
    public
        var pattern                    # -e PATTERN (always via -e, so a leading '-' is data); '' → rc 2
        var ignoreCase                 # -i
        var invert                     # -v
        var wordRegexp                 # -w
        var lineRegexp                 # -x
        var fixed                      # -F   ┐ both set → rc 2 at buildArgv
        var extended                   # -E   ┘
        var recursive                  # -r   (never -R: a directory symlink is not followed, R13)
        var lineNumber                 # -n
        var filesOnly                  # -l   ┐ both set → rc 2
        var filesWithoutMatch          # -L   ┘
        var countOnly                  # -c
        var onlyMatching               # -o
        var noFilename                 # -h   ┐ both set → rc 2
        var withFilename               # -H   ┘
        var maxCount                   # -m N   (kk.isInt AND >= 0; '' = off)
        var include                    # --include=GLOB ('' = off; more via addArg)
        var exclude                    # --exclude=GLOB
        var excludeDir                 # --exclude-dir=GLOB
        var binary                     # -U (--binary): read input in binary mode — see §2.6
        var nullData                   # -z  (records are NUL-terminated INPUT)
        var nullOut                    # -Z  (see §2.7: NUL records ONLY together with -l/-L)
        constructor Create             # [PATTERN [PATH...]]; assigns EVERY var; does NOT use `inherited`
        destructor  Destroy            # frees ${inst}_paths, then inherited
        proc paths                     # PATH... replaces the operand list ('' list = stdin grep)
        override func buildArgv        # grep [flags] -e PATTERN [extras] -- PATH...
        override func mapRc            # 0→0; 1→1 silent ("no match"); ≥2→1 + kk.debug
        static proc search             # PATTERN PATH... → `grep -r` stream; ≥1 path required (§2.5)
end
```

argv shape, pinned: `grep` `[-i] [-v] [-w] [-x] [-F|-E] [-r] [-n] [-l|-L] [-c] [-o]
[-h|-H] [-m N] [--include=G] [--exclude=G] [--exclude-dir=G] [-U] [-z] [-Z]`
`-e PATTERN` `[EXTRA ARGS from addArg]` `--` `PATH...`. With no paths there is no
`--` (grep then reads stdin). Booleans are `1` = on, anything else = off. No `-P`
(PCRE is optional in GNU grep builds and absent from the ERE-only house line,
tregex). No `--color` ever (the output is data).

buildArgv rc 2 (nothing runs, `kk.debug` names the reason): `cmd` empty; `pattern`
empty (`-e ''` matches every line — refused, not pinned as intentional); `-F`+`-E`;
`-l`+`-L`; `-h`+`-H` (grep accepts the last two pairs with last-flag-wins /
empty-output semantics, and buildArgv's fixed order would make the answer depend on
something the caller never wrote); `maxCount` not an int or negative (grep 3.0
takes `-m -1` as "no limit" silently).

### 1.4 Not in scope (wontfix / deferred)

1. **BSD/macOS flag dialects** (D4).
2. **Reading the tool's stderr** into RESULT — passes through; a caller wraps.
3. **Interactive tools** and anything that needs a tty.
4. **`TProcess` parity** (pipes to stdin, `poWaitOnExit`, environment editing,
   `CurrentDirectory`) — `stdinFrom FILE` may come later as a sink option; not now.
5. **Option validation against the tool's own `--help`** — the wrapper's typed set
   IS the validated surface; `addArg` is the documented escape hatch and is passed
   through verbatim.
6. **grep `-P`, `--color`, `-A/-B/-C` context** (context lines break the
   one-record-one-match model of the sinks; a caller that wants them uses `addArg`
   and `run`).
7. **Binary files.** grep prints `Binary file X matches` on **stdout**, so it arrives
   as a record through every sink (a first-hour hit under `-r` over a source tree).
   `addArg -a` or `addArg --binary-files=text` is the escape hatch; modelling
   `-a`/`-I` is a later wave. The README says so next to the `-r` example.

---

## 2. Design decisions

### 2.1 Three per-instance arrays, all freed by the destructor

`${inst}_args` (caller extras, persistent), `${inst}_argv` (built, rebuilt on every
run/sink), `${inst}_paths` (tgrep only). Created with `declare -g -a` in the
constructor, reset with `local -n a="${__inst__}_argv"; a=()` (verified on both
bashes), removed with `unset` in the destructor (verified: after `g.delete` none of
`g_paths g_args g_argv g_data` exist). A descendant destructor frees its own arrays,
then `inherited` (chains correctly — verified).

`argv NAME` validates the out-name with `kk._outName NAME __tu_ __tg_` **and** a
unit helper that refuses `${inst}_args|_argv|_paths` — the `TQueueStack._outName`
shape (`tqueuestack.sh:189`), with one difference: that helper answers rc 1 and its
caller converts to rc 2; here the conversion is the member's job and 001 asserts
rc 2 on `${inst}_args`.

**Constructors assign every declared `var`** — booleans to `0`, strings to `''`,
`_lastRc` to `-1`, no exception. kklass binds a property as a nameref onto
`${inst}_data[NAME]`; an unassigned one is an **unbound variable under `set -u`**
(`kklass.sh:363`), and `.new` over a still-live instance does not clear `_data`, so
an unassigned var can also inherit the previous instance's value. 001/004 assert
that `declare -p ${inst}_data` lists every declared var right after `new`.

**A descendant constructor does not use `inherited`.** The Pascal front-end
rewrites both `inherited` and `inherited Create` in a constructor body to
`parent.constructor "$@"` (`kklass_pascal.sh:166`), forwarding the descendant's
arguments unchanged — `TGrep.Create PATTERN PATH...` would hand TUtil
`cmd=PATTERN, args=(PATH...)` and every path would be emitted twice (verified: the
hit list doubled). `TGrep.Create` calls `parent.constructor grep` explicitly (cmd
set, args empty), then assigns its own vars and `${inst}_paths`. 004 pins that
`${g}_args` is empty after `TGrep.new g PAT PATH`.

### 2.2 buildArgv is the single truth, called silently

Every sink and `run` call buildArgv first, and it is the descendant's override that
runs (virtual dispatch from a base member to a TGrep override — verified). A
buildArgv that fails is `kk._return ""; return 2` + `kk.debug`, and the sink **runs
nothing**. `argv NAME` exposes the built array for tests: every option is pinned by
comparing the array, not by running grep.

**Inside a member body, an internal call to another member goes through
`kk.call_silent "$__inst__" NAME ARGS...`, never `$this.NAME`.** `$this.NAME`
compiles to `$__inst__.call NAME`, which does not set `__kk_return_silent`; the
callee's `kk._return` then **prints** whenever the outer member runs under `$( )`,
on the LHS of a pipe or inside `<( )` — exactly the three positions `run` is
documented for. Measured: `od -c < <(v.run)` showed `2A\nB\n0` (buildArgv's count,
the tool's output, mapRc's value). `kk.call_silent` sets and restores the flag, keeps
RESULT, and still dispatches virtually (kklass test 112). `TGrep.search` is not
affected because the thin static dispatcher already runs with the flag set, but its
body uses the same spelling for uniformity. 002/003 pin `od -c < <(u.run)`
byte-exact against the bare tool.

### 2.3 run vs the sinks, and how a func sink answers

`run` executes `"${__tu_v[@]}" || __tu_rc=$?` in the foreground — **never bare**:
under `set -e` a failing external command inside a member aborts the caller before
`_lastRc` is stored (verified). stdout is inherited; no process substitution. The
raw rc goes to the per-instance `_lastRc` (two wrappers may interleave), `mapRc` is
applied, its RESULT becomes `run`'s rc.

Before executing, `run` and every sink check `command -v -- "$cmd" >/dev/null`
(a builtin, no fork). A missing command is rc 1 + `_lastRc=127` + one `kk.debug`
line, and **nothing runs** — otherwise bash prints its own unconditional
`command not found` on stderr, attributed to `kklass.sh`, which breaks §1.2's
"stderr only under the switch". This is deliberately stricter than TPipe, which
takes an arbitrary argv and does not pre-check (tpipe PLAN §2.5); TUtil owns `cmd`,
so it can.

A **func sink body is ordered**, because an explicit `return` skips the compiled
`kk._return` trailer and `kk._invoke` then restores the caller's RESULT
(`kklass.sh:399`) — a bare `RESULT=n; return 1` reaches the caller as rc 1 with the
caller's old RESULT (verified):

```bash
TPipe.toArray … -- "${__tu_v[@]}" || :     # rc read below via lastRc
local __tu_n="$RESULT"                      # the record count, saved IMMEDIATELY
TPipe.lastRc; _lastRc="$RESULT"
kk.call_silent "$__inst__" mapRc "$_lastRc"; local __tu_m="$RESULT"
kk._return "$__tu_n"; return "$__tu_m"      # RESULT = count, rc = mapped
```

The consumer-stop case (`TPipe.stop` inside the callback): TPipe already answers
rc 0 and `lastRc` shows 141, 143 or the producer's own exit; `mapRc` is **not** applied
then. `nul`/`crlf` translate to TPipe's `-0`/`-c`.

`run`'s stdout is the one deliberate deviation from §1.1 in this family: a stream
member prints by definition. It is named in the kcl README §2 row exactly as
tregex's echo deviation is, and in each unit README.

### 2.4 mapRc — one policy, one override point, and the partial-output case

Base: `0 → 0`; `127 → 1` + debug "command not found"; anything else `→ 1`, silent.
TGrep: `1 → 1` silent (no match is an answer); `≥ 2 → 1` + debug quoting the raw
rc (bad regex under `-E`, unreadable file, a directory operand without `-r`).

grep answers **2 while still delivering matches** when one file in the operand
list fails (`grep: missing.txt: No such file` on stderr, the other files' hits on
stdout, rc 2 — verified). `mapRc` still maps it to rc 1 (the call was not fully
successful) but the sinks keep whatever records arrived and **RESULT is the real
count** — the one place in this family where rc 1 does not imply `RESULT=''`. It
is named in the README and in the kcl README §2 row next to the `run` deviation.

### 2.5 `TGrep.search` — the one-liner is a tree search

`TGrep.search PATTERN PATH...`: `grep -r -e PATTERN -- PATH...` as a stream, rc
mapped. **`-r` is implied by definition** — the flagship example
`TGrep.search "needle" src/` names a directory, and without `-r` GNU grep 3.0
answers `Is a directory`, rc 2, zero records (verified; the first draft's G8/G9
contradicted each other on exactly this). At least one path is **required**: with
none, `grep -r` searches the current directory instead of stdin, which no caller
means by accident — rc 2, nothing runs. A caller that wants stdin or any option
builds an instance; the instance never implies `-r` (G8).

Implementation: a throw-away instance named `__tg_s_${BASHPID}_${__TG_SEQ}`, with a
unit-global monotonic `__TG_SEQ` bumped on entry (the `ktest_fixtures`
`_KT_BACKUP_SEQ` idiom). A fixed name would be **deleted by a nested `search`**
(one called from inside the callback of an outer search's `each` — verified: the
outer instance vanished). 005 pins the nested case. Cost: one instance
construction per call (ms), acceptable for a convenience whose body is a fork.

### 2.6 CRLF: text-mode tools, `crlf`, and `binary`

Measured on this platform (both bashes, a `x\r\ny\r\n` file): GNU **grep, sed and
gawk open input in text mode and strip the CR themselves**; `cat`, `head` and bash's
`read` keep it; a pattern containing a literal `\r` never matches; `grep -U`
restores byte fidelity. Consequences:

- `crlf` (default `0`) is a **no-op for TGrep/tsed/tawk** output; it exists for the
  coreutils wrappers (§7 thead/ttail) and for producers that are bash functions.
- `binary` (`-U`) is the only way to see the CR through grep; `binary = 1` plus
  `crlf = 1` is the documented combination for a byte-faithful pass over a CRLF
  corpus. The README shows the measurement table, not a symptom that cannot occur.

### 2.7 `-Z` and NUL records

`-Z` is NUL **termination** only together with `-l`/`-L`; with `-c` and with normal
output it only replaces the separator after the file name and records still end in
`\n` (verified on grep 3.0: `a.txt\0 2\n`). Feeding those to TPipe `-0` would
mis-frame every record. buildArgv therefore **derives** the sinks' `-0` from
`nullOut == 1 && (filesOnly == 1 || filesWithoutMatch == 1)`; `nul` stays the
caller's own manual override for other shapes. A private 23rd var `_nulDerived`
records that buildArgv set it, so the derivation is undone when the condition
stops holding and a caller-set `nul` is never touched (a set-only rule was not
idempotent — P2 worker finding). A plain `var` cannot set another var
(only a `property … write _setX` could), so `nullOut` never touches `nul`.

---

## 3. Pinned facts (P0/P2 turn each into a test)

| # | Fact | Test |
|---|---|---|
| U1 | `TUtil.new u printf '%s\n' a b; u.each cb` delivers 2 records; state kept | 001 |
| U2 | `argv` reflects `cmd` + `args` exactly; `addArg` appends; `clearArgs` empties; `--format=%H` reaches Create verbatim | 001 |
| U3 | `u.delete` leaves no `${inst}_args`/`_argv` (declare -p fails); every declared var is present in `_data` right after `new` | 001 |
| U4 | `cmd=''` → every runner is rc 2, nothing runs (a here-string on stdin stays unread) | 001 |
| U5 | `cmd=no_such_tool_xyz` → rc 1, `lastRc` 127, exactly one stderr line under debug, **none** without it (the pre-check) | 001 |
| U6 | a callback that calls `TPipe.stop` → sink rc 0, `lastRc` 141 or 143 (tpipe PLAN §2.3), no hang | 002 |
| U7 | `od -c < <(u.run)`, `$(u.run)` and `u.run \| od -c` are byte-identical to the bare tool (no leaked digits) | 002 |
| U8 | a func sink answers RESULT = count **and** rc = mapped, direct and under `$( )` | 002 |
| G1 | argv for every flag, singly and combined, byte-exact; `-e` always; `--` before paths; no paths → no `--`; `${g}_args` empty after `new g PAT PATH` | 004 |
| G2 | `-F`+`-E`, `-l`+`-L`, `-h`+`-H`, empty pattern → rc 2 at buildArgv, nothing runs | 004 |
| G3 | `maxCount=abc` → rc 2; `maxCount=-1` → rc 2; `maxCount=08` → `-m 8` via `$__KK_INT` (the OUTVAR form writes through the property nameref and would mutate state — not used) | 004 |
| G4 | pattern `-v` is searched, not parsed (via `-e`) | 004 |
| G5 | no match: `each` rc 1, RESULT 0, `lastRc` 1, silent | 005 |
| G6 | `extended = 1` + pattern `(`: rc 1, `lastRc` 2, one debug line; the same pattern with `extended` off is a literal `(` (rc 0/1, no debug) | 005 |
| G7 | `filesOnly=1; nullOut=1` → `toArray` yields names with spaces and a newline intact (derived `-0`); `countOnly=1; nullOut=1` → records still `\n`-framed | 005 |
| G8 | instance on a directory without `recursive` → rc 1, `lastRc` 2, zero records; `TGrep.search x dir/` → hits (implied `-r`); `search x` with no path → rc 2 | 005 |
| G9 | the README example under lastpipe == the `--` form == `g.each` with `recursive = 1` (same hits, same order) | 005 |
| G10 | one missing file among good ones: records delivered, RESULT = their count, rc 1, `lastRc` 2 | 005 |
| G11 | nested `search` from inside an outer search's callback: both complete, outer instance survives | 005 |
| G12 | `-r` does not descend a directory symlink; `-R` would; a symlink named on the command line is followed even under `-r` (real symlink via `kt_make_symlink`; skipped with `kt_test_pass` when the helper cannot make one, as tdirectory/033 does) | 005 |

---

## 4. Parity & test model

Oracle = the bare GNU tool on the same fixture tree. The tree is built under
`$_KT_TMPDIR` with `kt_fixture_tmpdir_create` / `kt_fixture_create_structure` and
torn down by the framework; **a test file never installs its own `trap … EXIT`** —
it would replace `ktest.sh`'s trap, which runs `kt_fixture_teardown` and prints the
`__COUNTS__` line the runner parses. Fixture contents: names with spaces, a newline
(creatable on this NTFS/msys box — verified), a leading `-`, UTF-8; CRLF files; a
directory symlink through `../../tdirectory/tests/symlink_helper.sh` (plain `ln -s`
here produces a **directory copy**, which grep then descends for the wrong reason).

The behavioural files (005/006) start by asserting `grep --version` begins with
`grep (GNU grep) `; otherwise the behavioural half is a loud SKIP (this machine
carries a non-GNU `grep` from Embarcadero on PATH after the msys ones). The argv
pins (004) never run grep and are the fast half of the suite.

Red-first: for P0 the unit file does not exist, so the house answer is the thashset
one — the test files are written against the **stubbed skeleton** of P0.1 (sinks
answering the `__TUTIL_PENDING__` sentinel through `kk._return`, rc 2) and must be
red there; the count goes in the ledger. Later phases stash the unit file.

| file | phase | what |
|---|---|---|
| `tutil/tests/001_Core.sh` | P0 | U1–U5, lifecycle, buildArgv base, mapRc base, `argv` out-name validation (rc 2 on `state`, on `${inst}_args`), every-var-assigned |
| `tutil/tests/002_Sinks.sh` | P1 | U6–U8, each/toArray/toList/first/count vs TPipe direct and vs bare bash; `nul`/`crlf` translation; nested dispatch through three frames (`g.each` → `TPipe.each` → `r.onLine`) |
| `tutil/tests/003_Contract.sh` | P1 | `set -eu` path incl. a failing tool under `run`; debug switch prints one line per rc 2 path and nothing otherwise; BASHPID zero-fork probe in the callback |
| `tgrep/tests/004_Argv.sh` | P2 | G1–G4 |
| `tgrep/tests/005_Search.sh` | P2 | G5–G12, fixture tree, GNU banner gate |
| `tgrep/tests/006_Contract.sh` | P2 | `set -eu`, both TPipe forms with the wrapper as producer |

---

## 5. Phases

### P0 — TUtil core (gate: 001 green on both bashes, sweep)

- P0.1 `tutil.sh`: guard, locale, class per §1.2 with the sinks as stubs that
  answer `kk._return "__TUTIL_PENDING__"; return 2` (a func stub that does not
  `kk._return` leaves the caller's RESULT in place and cannot be asserted);
  `Create` (assigns every var), `Destroy`, `buildArgv` (base), `addArg`,
  `clearArgs`, `argv`, `mapRc` (base), `lastRc`.
- P0.2 `run` (pre-check, foreground exec with `|| rc=$?`, `_lastRc`, mapRc through
  `kk.call_silent`).
- P0.3 tests 001; README first cut (TProcess kinship, the generic runner example).

### P1 — sinks through TPipe (gate: 002 + 003 green, sweep)

- P1.1 `each`/`toArray`/`toList`/`first`/`count` per §2.3; stubs removed; a test
  that no member answers `__TUTIL_PENDING__` any more.
- P1.2 tests 002, 003.

### P2 — TGrep (gate: 004–006 green, sweep)

- P2.1 `kcl/tgrep/tgrep.sh`: class per §1.3, `Create` per §2.1 (no `inherited`),
  `buildArgv` override (argv shape and rc 2 list pinned in §1.3, derived `-0` per
  §2.7), `mapRc` override, `paths`, destructor, `search` per §2.5.
- P2.2 tests 004–006 with the fixture tree; `tgrep/README.md`.

### P3 — closeout (gate: bench in READMEs, sweep on both bashes)

- P3.1 `tutil/bench.sh`: cost of `argv` (fork-free), of `run` on `true`, of
  `each` over 10k records vs TPipe direct (must be ≤ 1.1×, the delegation is one
  call); `tgrep`: `search` vs bare grep on a 10k-line file (≤ 1.3×, the instance
  construction is the delta).
- P3.2 READMEs final (the three forms with `recursive = 1` / `search`, the rc table
  incl. the partial-output case, the argv table for TGrep, the CRLF measurement
  table, the binary-file note), `docs/TUtil.md` (TProcess comparison),
  `TEST_COVERAGE_NOTES.md` for both units, kcl README §2 rows for tutil and tgrep
  naming both deviations, ledger COMPLETE with SHAs.

**DONE 2026-09-11.** `tutil/bench.sh`, `tutil/tests/004_Bench.sh` (8 cases),
`tutil/docs/TUtil.md`, `tutil/TEST_COVERAGE_NOTES.md`, `tgrep/bench.sh`,
`tgrep/tests/007_Bench.sh` (9 cases), `tgrep/TEST_COVERAGE_NOTES.md`, both
READMEs rewritten, two kcl `README.md` §2 rows (Eighteen → Twenty).
`tutil.sh` and tests 001–003, 005, 006 unchanged; `tgrep.sh` and
`tgrep/tests/004_Argv.sh` changed only for the P3-F1 fix below.
Suites: **tutil 172/172, tgrep 184/184** on bash 5.2.37 and on 5.3.9, threaded,
and again under `--mode single`. Both benches rc 0 under `bash -eu` on both
bashes. Measured with the runner idle (5.2.37 / 5.3.9):

| gate / number | 5.2.37 | 5.3.9 |
|---|---|---|
| **P3.1 gate** `u.each` vs `TPipe.each` DIRECT on the same argv (≤ 1.1×) | 2030 ms vs 2078 ms — **0.97×** | 2089 ms vs 2072 ms — **1.00×** |
| `u.toArray` vs `TPipe.toArray` direct (published) | 1873 ms vs 1782 ms — 1.05× | 1798 ms vs 1874 ms — 0.95× |
| `u.each` + an instance-member callback (published) | 4428 ms — 2.18× | 4290 ms — 2.05× |
| `buildArgv` / `argv NAME`, base class | 266.8 / 779.2 µs | 295.9 / 793.0 µs |
| `u.run` on `true` (per CALL, not per record) | 1026.4 µs | 1123.4 µs |
| **P3.1 gate** `TGrep.search` vs a bare `grep -r`, 10 000-line corpus (≤ 1.3×) | 33.77 ms vs 28.65 ms — **1.17×** | 33.30 ms vs 26.97 ms — **1.23×** |
| `TGrep.new` + `.delete` — *the search delta* | 2547.8 µs | 2410.4 µs |
| `g.count` vs `grep -c` / `countOnly` + `toArray` vs `grep -c` (published) | 1.47× / 1.09× | 1.50× / 1.10× |
| `buildArgv` / `argv NAME`, 22 typed options | 895.5 / 1508.2 µs | 909.6 / 1637.0 µs |
| forks per record (tutil) / per call (tgrep) | 0 / 1 (grep) | 0 / 1 |

Three worker notes, all recorded in the ledger:

* **P3-F1 — found while writing `docs/TUtil.md`, FIXED in the same phase.**
  §2.7's `_nulDerived` was claimed whenever the derivation *condition* held, even
  when `nul` was already `1` because the caller set it — so the next build that
  stopped deriving cleared the caller's own `nul`. The bookkeeping has to tell
  three states apart (derived = ours, undo it; caller-set = never touch; off) and
  was only telling two. The fix is one guard inside the deriving branch of
  `TGrep.buildArgv` — `if [[ "$nul" != 1 ]]; then nul=1; _nulDerived=1; fi` —
  with the un-derive branch unchanged. Red-first: the new case in
  `tgrep/tests/004_Argv.sh` §G failed **1 of 184** against the unguarded code;
  green 184/184 after. The §2.7 claim "a caller-set `nul` is never touched" is
  now true. `tgrep.sh` and `tgrep/tests/004_Argv.sh` are the only sources this
  phase touched, on the reviewer's instruction after the first P3 report.
* **Medians, not means, for the tgrep bench.** Each number there is one process
  start plus a scan, and one start in twenty takes ~200 ms on this box: timing
  the two shapes in separate blocks made the search ratio read 1.07×, 1.19×,
  1.23×, 1.46× and 1.51× across consecutive runs of identical code. The shapes
  are now interleaved one per iteration and the published ratio is the median.
* **Warm every measured shape.** The first sink call in a process pays a one-off
  bind cost; without warming, whichever shape ran first was penalised and
  tutil's `each` ratio read 1.13× instead of ~1.00×.

The gates in the two `*_Bench.sh` files are set at **5×** (tutil) and **10×**
(tgrep) rather than at the measured values, because ktests runs test files
threaded with 8 workers: tutil's two cases have been seen at 0.94× and 1.87×
under that load, and tgrep's search case at 4.18× on one run and 1.16× on the
next. Each file's header records those numbers.

---

### P4 — D6 final: `subshellOk` (owner ruling 2026-09-15, Q9; same worker cycle as tpipe P3)

- P4.1 `var subshellOk` (assigned `0` in `Create`; TGrep inherits it and does not
  redeclare it); `tutil._prep` appends `-s` to the flag array when `subshellOk == 1`.
  The dynamically scoped `KK_SUBSHELL_OK=1` reaches TPipe through every wrapper
  without any TUtil code (verified), so the property is the object-style spelling of
  the same switch and nothing else.
- P4.2 Tests: 002/003 cases that run `toArray`/`toList` under `$( )` now expect ONE
  `kk.warn` line (the tpipe template with `MEMBER` = the TPipe member) and its
  silence under `subshellOk = 1`, under `KK_SUBSHELL_OK=1 u.toArray …` and under
  `VERBOSE_KKLASS=quiet`; `u.count`/`u.first` under `$( )` stay silent; `u.each` with an
  instance-member callback under `$( )` warns, with a plain function does not. 001 U3
  lists `subshellOk` among the vars present after `new`. tgrep 004 pins that
  `${g}_data` carries `subshellOk=0` after `new` and 006 has one `subshellOk = 1`
  case. READMEs (tutil member table + reserved names, tgrep surface), coverage notes,
  ledger entry.

---

## 6. Bash and kklass traps to respect

- `$this.NAME` inside a member **prints** the callee's `kk._return` value under
  `$( )` / `|` / `<( )`; use `kk.call_silent "$__inst__" NAME …` (§2.2).
- A `func` that must answer both RESULT and a non-zero rc ends with
  `kk._return V; return N` — a bare `RESULT=V; return N` loses V (§2.3).
- `inherited` in a **constructor** forwards `"$@"` (§2.1); call
  `parent.constructor ARGS` explicitly.
- Every declared `var` is assigned in the constructor; an unassigned one is unbound
  under `set -u` and may carry a previous instance's value (§2.1).
- A descendant never declares a `var` named like an ancestor member (§1.2).
- `"${argv[@]}" || rc=$?`, never bare, in `run` (§2.3).
- `"${argv[@]}"` under `set -u` with an empty array: fine on both targets, but
  buildArgv never leaves it empty (cmd is element 0 or it is rc 2).
- A boolean property is tested as `[[ "$ignoreCase" == 1 ]]`, never `(( ignoreCase ))`
  (a string there is 0 silently, or an arithmetic injection — §1.5).
- `maxCount` goes through `kk.isInt` **before** it is placed after `-m`, read back
  from `$__KK_INT`, and `>= 0` is checked separately.
- `$this.buildArgv` / `kk.call_silent … buildArgv` is the virtual call; `inherited
  buildArgv` in a descendant is the static one — TGrep does not call inherited (it
  builds the whole array itself), TUtil's base version is for plain instances.
- Never `unset "${inst}_argv[…]"` in double quotes (G2-01); rebuild with
  `local -n a="${__inst__}_argv"; a=()`.
- Under `$( )` the sinks lose the instance's `_lastRc` update — the README says so
  once, the same line every instance unit carries.
- grep with **no** path reads stdin; an instance with no paths therefore reads stdin,
  and in the `--` form of TPipe that stdin is the calling shell's — document, do not
  "fix". `search` is the exception (§2.5).
- A plain `var` property read at a CALL SITE (`u.crlf`) PRINTS the value on stdout
  and leaves `RESULT` empty — unlike a `func`. `$(u.crlf)` is the only correct read
  spelling outside a member; inside a member the var is a nameref (`$crlf`). No
  member body or test may do `u.crlf; use "$RESULT"` (P0 worker finding).
- `subshellOk` is a plain 0/1 var like the others: tested as `[[ "$subshellOk" == 1 ]]`,
  assigned in every constructor, never redeclared by a descendant (D6 final Q9).
- Every sink declares `local __TPIPE_QUIET=1` before delegating to TPipe: `tpipe._ret`
  prints under any `BASH_SUBSHELL > 0`, so without it `$(u.count)` read `22` (TPipe's
  print plus the sink's own `kk._return`) and `u.each cb | cat` carried the count.
  A `>/dev/null` on the TPipe call is NOT the fix — it swallows the callback's and
  `.Add`'s own stdout under `$( )` (P1 finding).
- `first` answers rc 1 whenever `TPipe.first` answered non-zero — "no record" is the
  answer regardless of the producer's own rc (`mapRc` still runs for its debug line).
- A trailing CR is dropped from a word of a compound array assignment on this
  platform (`A=( $'cr\r' )` → length 2); CR-bearing fixtures go through a scalar or
  `printf -v` (P1 finding, also in tpipe PLAN §6).
- Test files: no own `EXIT` trap; fixtures through ktests; symlinks through the
  tdirectory helper (§4).

---

## 7. Template for the next wrappers (one unit each, own PLAN + ledger)

Verified on the installed versions (2026-09-10): `sed -e EXPR -- FILE` and
`-- -weird.txt` work; `gawk -e PROG FILE` works on 5.0 and 5.4; `head -n 1 -- FILE`
works; findutils 4.10 accepts `-name X -maxdepth 1` without a warning. `--` is
**not** a full option terminator for sed's expression slot (`sed -- -e …` errors),
which is why every wrapper emits its expression flags first, then `--`, then paths.

| unit | tool | typed options (first wave) | rc map | notes |
|---|---|---|---|---|
| tsed **(built, P0)** | GNU sed 4.9 | `expr` (the first `-e`) **plus** `addExpr`/`clearExprs` over `${inst}_exprs` and `scriptFile` (`-f`); `extended` (`-E`), `quiet` (`-n`), `separate` (`-s`), `nullData` (`-z` → derived `-0`), `binary` (`-b`), **`sandbox` (`--sandbox`, default 1)**, `inPlace` (`-i`) + `backupSuffix` (attached); `inPlace`/`--debug` → **the five sinks refuse (rc 2), `run` only** | 0→0; 1, 2, 4 → 1 + debug ("sed exited N (a sed error, or the script's q/Q N)"); 127 base; any other (a script's `q N`/`Q N`) → 1 **silent**, raw in `lastRc` | every option (typed and extra) **before the first `-e`** — sed compiles each `-e` when it reads it; `-e` list, `-f`, then `--` + paths; no script at all is rc 2; `inPlace`/`nullData` **derive `-b`** (text mode rewrites CRLF to LF on disk); a deny-list refuses extras that duplicate a typed property; a missing input keeps the other files' records (rc 2), an I/O error (rc 4) stops at that operand; `crlf` is a no-op unless `binary`; `TSed.edit EXPR PATH...` one-liner (sandbox forced). This unit added the **`TUTIL_OUT_SUFFIXES`** registry (`_args _argv _paths` + `_exprs`) with the same two guards as the prefix one |
| tawk **(built, P0)** | GNU Awk 5.0.0 (bash 5.2.37) / 5.4.0 (bash 5.3.9) | `program` (the first `-e`) **plus** `addProgram`/`clearPrograms` over `${inst}_progs` and `programFile` (`-f`, after the chunks; `-` refused); `fieldSep` (`-F`); **`setVar NAME VALUE`** / `clearVars` over indexed `${inst}_vnames`/`_vvals` — **verbatim**, emitted as `-v NAME=enc(VALUE)` (every `\` doubled, newline as `\n`, a leading `@` as `\100`) after the extras, insertion order, a repeated NAME replaced in place; `nullData` (`-v RS='\0' -v ORS='\0'` → derived `-0`), `binary` (`-v BINMODE=3`), **`sandbox` (`--sandbox`, default 1, fail-closed)**, `inPlace` (`-i /usr/share/awk/inplace.awk`, **absolute**; requires `sandbox = 0`) + `backupSuffix` (`-v inplace::suffix=`); `inPlace` → **the five sinks refuse (rc 2), `run` only**; static `TAwk.apply PROGRAM PATH...` (sandbox forced, `''` and no path rc 2) | 0→0; 1, 2 → 1 + debug ("gawk exited N (a gawk error, or the program's exit N)"); 127 base; any other (a program's `exit N`) → 1 **silent**, raw in `lastRc` | an empty `-e ''` is never emitted (gawk drops it and would compile the first path as THE program), no program at all is rc 2; a path gawk reads as an **assignment** (`[NS::]NAME=…`) is rc 2 (pass `./NAME=…`); the `addArg` deny-list follows gawk's getopt incl. **any prefix** of a denied long name and the **`-W` spelling**, plus `--`, a non-option word and a dangling `-v`/`--assign`/`-W`; `-P`/`-c` refused while BINMODE is derived; `inPlace`/`nullData` **derive `BINMODE=3`** (text mode strips the CR); a missing input file is **FATAL** (later files never read / edited); a directory is skipped with a warning (rc 0). Registers `__taw_` and the suffixes `_progs _vnames _vvals` |
| tfind **(built, P0)** | findutils 4.10.0 | `name`, `iname`, `type`, `maxDepth`, `minDepth`, `newer`, `followSymlinks` (`-L`), `print0` (→ derived `-0`) | 0→0; else →1+debug | start points are **positional and come FIRST** (the reverse of grep/head) and **no `--` is ever emitted** — it ends the option list only, so an empty start point or one matching `^[-!(]` is rc 2; `-L` is accepted only before the start points, hence the typed `followSymlinks`; global options (`-maxdepth`) before the tests by convention, extras, then `-print0` last; depths go through `kk.isInt` and are emitted from **`$__KK_INT`** (a verbatim `+1` is the tool's rc 1) — the opposite of thead/ttail; `print0 = 1` refuses any **action** word among the extras (two actions corrupt the NUL framing); deviations: partial output on a missing start point, the tool's stderr, and `-exec … {} \;` leaving rc 0. This unit turned `tutil._badOut`'s hard-coded prefix list into the **`TUTIL_OUT_PREFIXES`** registry (§5 of the README), with two guards: the registry's own name is refused as an out-name, and an empty/unset/non-array registry refuses **every** name |
| thead / ttail | coreutils 8.32 | `lines` (`-n`), `bytes` (`-c`), `follow` (tail `-f`): **run/each/first stream, `toArray`/`count`/`toList` refused** (ttail PLAN §2.1), `zeroTerminated` (`-z`) | 0→0; 1→1+debug | count = regex `^[+-]?[0-9]+$` + 19-digit guard, verbatim, **NOT `kk.isInt`** (thead PLAN §2.2); these KEEP the CR — `crlf` matters here |

Each follows the P2 shape above: argv pins first (fast, no tool run), then the fixture
suite (GNU banner gate first), then the contract file.

## 8. Critic pass (2026-09-10)

An Opus critic reviewed the first draft against the live tree with 23 probe scripts
on both bashes. Findings and where each landed:

| # | sev | finding | landed in |
|---|---|---|---|
| 1 | BLOCKER | `$this.func` inside a member prints the callee's `kk._return` under `$( )`/`\|`/`<( )` — `run` leaked digits into its stream | §2.2, §6 |
| 2 | BLOCKER | `inherited` in a constructor forwards `"$@"`; TGrep paths doubled | §2.1, §6 |
| 3 | BLOCKER | an unassigned `var` is unbound under `set -u`; `.new` over a live instance keeps stale `_data` | §2.1, §6, U3 |
| 4 | BLOCKER | G8 and the flagship example contradicted: `search x dir/` without `-r` is rc 2, zero records | §2.5 (`search` implies `-r`, ≥1 path), G8/G9 |
| 5 | BLOCKER | a func cannot answer RESULT + non-zero rc with `RESULT=; return` | §2.3, §6, U8 |
| 6 | MAJOR | `(` is a literal under BRE; G6 wrong without `-E` | G6 |
| 7 | MAJOR | plain `ln -s` makes a directory copy on this box | §4, G12 |
| 8 | MAJOR | grep/sed/gawk strip CR in text mode; `crlf` is a no-op for them; `-U` missing | §2.6, `binary` var, §7 |
| 9 | MAJOR | a test's own `EXIT` trap kills ktests' trap | §4, §6 |
| 10 | MAJOR | `-Z` is NUL termination only with `-l`/`-L`; a `var` cannot set `nul` | §2.7, G7 |
| 11 | MAJOR | grep rc 2 with partial hits; `Binary file X matches` is a stdout record | §2.4, §1.4 item 7, G10 |
| 12 | MAJOR | bare `"${argv[@]}"` aborts the caller under `set -e` | §2.3, §6 |
| 13 | MAJOR | fixed throw-away name `__tg_s` clobbered by a nested `search` | §2.5, G11 |
| 14 | MAJOR | no binary pinned; a non-GNU grep is on PATH here | header, §4 |
| 15 | MAJOR | missing `cmd` → bash's own unconditional stderr line | §2.3 pre-check, U5 |
| 16 | MINOR | `var` vs inherited method of the same name: method wins silently | §1.2 reserved names |
| 17 | MINOR | `kk.isInt` accepts negatives; `-m -1` = no limit; OUTVAR form writes through the nameref | §1.3, G3, §6 |
| 18 | MINOR | `-h`+`-H`, `-l`+`-L` accepted by grep with order-dependent results | §1.3 rc 2 list, G2 |
| 19 | MINOR | empty pattern matches everything; no decision | §1.3 (rc 2) |
| 20 | MINOR | sed `--` asymmetry unexplained | §7 |
| 21 | MINOR | `TStringList.Add` may answer rc 1 (dupError) — TPipe's `toList` guards it; the count is "records offered" | tpipe PLAN §2.4 |
| 22 | NIT | out-name helper returns rc 1 in tqueuestack; convert to 2 | §2.1 |
| 23 | NIT | a func stub without `kk._return` cannot be asserted | §5 P0.1 |

Verified correct by the critic (not to be re-probed): static + variadic constructor +
instance members without static vars keep the thin dispatcher; `--format=%H` reaches
Create verbatim; base→override virtual dispatch across files; destructor `inherited`
chain frees everything; `declare -g -a` + nameref reset + `unset`; `TGrep.search`
as a `<( )`/`|` producer is clean; `-e` with a leading-`-` pattern; `-Z -l` with a
newline in a name; `-z`; `--include` with `-r`; `-m 8` and `-m8`; `-F`+`-E` is
grep rc 2; `-r` vs `-R` on a real symlink; `RESULT=-1` has corpus precedent
(tarray, tlist); the README §2 row is the house mechanism for a deviation.
