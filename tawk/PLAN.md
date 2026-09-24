# TAwk — GNU `gawk` wrapper over TUtil (kcl/tawk)

**Status: COMPLETE (P0–P1).** P0 DONE 2026-09-23 (kcl `2472b04`), P1 DONE
2026-09-24 (`<SHA-TA1>`) — see §5 and [`tawk_ledger.json`](tawk_ledger.json).
Originally **PLANNED, critic-hardened (2026-09-23)**. Owner: "push потом
tawk" (2026-09-23); four design questions answered by the owner before the plan
(§2.0). A critic pass (§8: 1 blocker, 7 majors, 6 minors, 6 nits — all folded in)
overturned the first draft's `setVar` mechanism: `-v` DOES round-trip every byte
when the value is encoded (§2.3); the supervisor's planning probe that said
otherwise had been corrupted by the Bash tool collapsing `\\` in an inline command.
The fifth and last wrapper of tutil PLAN §7; everything tgrep, thead, ttail, tfind
and tsed settled applies. **TSed is the closest model** — read `kcl/tsed/PLAN.md`
(all of it, incl. §8) and `kcl/tsed/tsed.sh` first.

**Source of truth:** GNU Awk, **two versions**: bash 5.2.37 resolves Git for
Windows' `/usr/bin/gawk` = **5.0.0**; bash 5.3.9 resolves msys64's = **5.4.0**.
They differ in message texts, in `INPLACE_SUFFIX` (5.4 only), in long-option
abbreviations (`--t`/`--tr` are `--traditional` on 5.0, ambiguous on 5.4; `-I`, `-k`
exist on 5.4 only), and in the sandbox (5.4 refuses `ARGV[ARGC++]=…`; 5.4 with
`--sandbox -M` blanks `ARGV[1]` and reads stdin). D4: GNU dialect, PATH-resolved
binary, banner gate in the behavioural tests (`GNU Awk `).
**Base:** `TAwk : TUtil`. **Ledger:** `kcl/tawk/tawk_ledger.json`. **Prefix:**
`__taw_` (appended to `TUTIL_OUT_PREFIXES`); `_progs`, `_vnames`, `_vvals` appended to
`TUTIL_OUT_SUFFIXES`. No `static var`. Sources `../tutil/tutil.sh` only.

---

## 1. Scoping

### 1.1 The tool, measured (both gawk versions unless noted)

| probe | result |
|---|---|
| program sources | several `-e PROG` and `-f FILE` are concatenated **in argument order**; each `-e` is compiled as its own source (a chunk must be complete: `-e 'BEGIN{' -e 'print 1}'` is rc 1; `@namespace` resets per chunk); **`-e ''` is dropped with a warning** — if that leaves no program, the first operand after `--` is compiled as the program (syntax error, or, for a path like `1`, a valid program that reads stdin) |
| no program | the first operand is the program text; it may read **stdin** (a planning probe hung) |
| options end | at the first non-option word: a stray word among the options becomes THE program and everything after it (`-e`, `--`, paths) becomes file operands (unlike sed, which reorders) |
| `--` | ends the options; `gawk -e P -- -weird` reads the file `-weird` |
| `-W long-option` | every long option also has a `-W` spelling, attached or separate, abbreviable, bundle-able (`-W so=…`, `-bW source=…`); a dangling `-W` takes the next word as its argument |
| operand `NAME=VALUE` | an **assignment**, not a file — also namespaced (`a::b=v`, `awk::x=v`); a file literally named so must be passed as `./NAME=…`; `1x=v`, `é=v`, `x.y=v`, `C:/x=y`, `C:\x=y` are files |
| rc | `0` ok; **`1`** syntax error / fatal runtime; **`2`** a missing input file — **FATAL**: the files BEFORE it are processed, the files after it are never read (like sed's rc 4, not its rc 2) — a missing `-f` file, a sandbox violation; **`exit N`** from the program, N mod 256 (`exit 300` → 44, `exit -1` → 255); a directory operand is skipped with ``gawk: cmd. line:1: warning: command line argument `DIR' is a directory: skipped`` (identical on both; corrected at P0 — backtick and the `cmd. line:1:` prefix), rc 0 (fatal rc 2 under `--posix`/`-c`) |
| `-v NAME=VALUE` | processes escape sequences; **round-trips every byte** when the value is encoded: every `\` doubled, every newline written `\n`, a leading `@` written `\100` (else `@/…/` is a typed regexp) — measured byte-exact on both versions over a matrix incl. `\t`, `\\`, a trailing `\`, `\`+newline, `$'"`, UTF-8, `@/foo/`, `@`, CR, `\xff`, `\u0041`, `/c/foo`, ` 010 ` (`typeof` preserved); an illegal name or a builtin/keyword is fatal rc 2 |
| `-F FS` | FS is a regex / escape-processed (`-F'\t'` = tab) |
| CR | text mode strips the CR on file and stdin input; **`-v BINMODE=3`** keeps it; gawk never writes CRLF; `--posix`, `-P`, `-c`, `--traditional` silently disable BINMODE |
| NUL records | `-v RS='\0' -v ORS='\0'` (both needed); an unterminated last NUL record comes out terminated |
| last record without `\n` | `print` appends ORS: an unterminated last line comes out terminated |
| `--sandbox` | refuses `system()`, output redirection incl. `> "/dev/stderr"` and `> "/dev/stdout"`, `\|`, `\|&`, `"cmd" \| getline`, **input** redirection `getline < "f"` (fatal rc 2), extensions (incl. `-i inplace`), and on 5.4 adding files to ARGV; `@include "file"` is allowed (and its `system()` still refused); `-d`/`-p`/`-o` still WRITE files under the sandbox |
| `-i inplace` | resolved through **AWKPATH** (`.:/usr/share/awk` by default — a planted `./inplace.awk` loads instead, and runs with the sandbox off); `-i /usr/share/awk/inplace.awk` loads the real one (its `@load` uses AWKLIBPATH, no `.`) on both; edits the files; END output still goes to stdout, ENDFILE output into the file; `exit` mid-file truncates that file and leaves later files untouched; a missing file stops there (earlier files edited, later untouched); a fatal runtime error leaves the file untouched; text mode rewrites CRLF to LF, `-v BINMODE=3` keeps the CR; backup: `-v inplace::suffix=.bak` (both; `INPLACE_SUFFIX` 5.4 only) |
| `-f FILE` | resolved through AWKPATH (`-f getopt.awk` silently loads `/usr/share/awk/getopt.awk`); `-f -` reads the program from stdin |
| writers / non-runners | `-o`/`--pretty-print` (program not run, file written), `-g`/`--gen-pot` (program not run, `.pot` on stdout), `-h`/`--usage`, `-V`/`--version`, `-C`/`--copyright` (text on stdout, program not run), `-d[FILE]`/`--dump-variables`, `-p[FILE]`/`--profile` (write files even under the sandbox), `-D`/`--debug` (reads commands from stdin — hangs), `-M`/`--bignum` (5.4 + sandbox: loses the input) |
| stdin | no file operand → stdin; `-` = stdin |
| stderr | unconditional; texts differ between 5.0 and 5.4 |

### 1.2 Surface

```bash
class TAwk : TUtil
    public
        var program         # the FIRST program chunk (-e); '' = none
        var programFile     # -f FILE ('' = off), emitted after the -e chunks; `-` refused
        var fieldSep        # -F FS ('' = off; awk semantics: regex, escapes processed)
        var nullData        # -v RS='\0' -v ORS='\0' → derives the sinks' -0 AND BINMODE=3
        var binary          # -v BINMODE=3 (also derived)
        var sandbox         # --sandbox, DEFAULT 1, fail-closed: dropped only for the exact string 0 (owner Q1)
        var inPlace         # -i /usr/share/awk/inplace.awk (derives BINMODE=3; requires sandbox = 0; sinks refused)
        var backupSuffix    # -v inplace::suffix=enc(SFX) (only with inPlace = 1; encoded like setVar — P0 review)
        var _nulDerived
        constructor Create  # [PROGRAM [PATH...]] — PROGRAM → program; assigns EVERY var; parent.constructor gawk
        destructor  Destroy # frees ${inst}_paths, _progs, _vnames, _vvals, then inherited
        proc paths          # PATH... replaces the operand list ('' list = stdin)
        proc addProgram     # CHUNK... appended to ${inst}_progs (after `program`); each chunk must be a complete source
        proc clearPrograms  # empties ${inst}_progs (not `program`)
        proc setVar         # NAME VALUE — VERBATIM (owner Q2; §2.3); a repeated NAME replaces in place (insertion order kept)
        proc clearVars
        override func buildArgv   # the pinned argv below
        override func mapRc       # 0→0; 1,2 → 1 + debug; 127 base; any other (exit N) → 1 silent
        override proc each        # inPlace = 1 → rc 2, nothing runs; else inherited
        override func toArray     # same (rc-preserving spelling)
        override func toList
        override func first
        override func count
        static proc apply         # TAwk.apply PROGRAM PATH... → `gawk --sandbox -e PROGRAM -- PATH...` stream; ≥1 path
end
```

argv shape, pinned: `gawk` `[--sandbox]` `[-F FS]` `[-v RS=\0 -v ORS=\0]`
`[-v BINMODE=3]` `[-i /usr/share/awk/inplace.awk [-v inplace::suffix=SFX]]`
`[EXTRA OPTIONS from addArg]` `[-v NAME=enc(VALUE) ...]` `[-e program]`
`[-e chunk ...]` `[-f FILE]` `[-- PATH...]` — `setVar` assignments after the extras
(so they win over an `addArg -v` of the same name), in insertion order; empty
chunks are never emitted.

### 1.3 Not in scope

1. `--lint`, `-b`, `-n`, `-O`, `-L`, `-t`, `-I`/`-k` (5.4), `-l`-free extensions:
   `addArg` where the deny-list allows (§2.2). 2. BSD awk / mawk (D4).

---

## 2. Design decisions

### 2.0 Owner decisions (2026-09-23)

| Q | decision |
|---|---|
| Q1 sandbox | as TSed: `sandbox = 1` by default, **fail-closed** (only the exact string `0` drops `--sandbox`) |
| Q2 variables | `setVar NAME VALUE` is **verbatim** — implemented as `-v NAME=enc(VALUE)` (§2.3). Awk-escape semantics remain available through `addArg -v …` |
| Q3 model | as TSed: `var program` + `addProgram`/`clearPrograms` + `programFile`; rc 1/2 → 1 + debug worded "gawk exited N (a gawk error, or the program's exit N)", any other status → 1 silent, raw in `lastRc`; a deny-list for `addArg` |
| Q4 in-place | as TSed: `inPlace` + `backupSuffix`, `run` only, the five sinks overridden (rc 2), `inPlace` derives `BINMODE=3`; it additionally **requires `sandbox = 0`** (the sandbox refuses the inplace extension) |

### 2.1 Everything the family decided applies verbatim

Constructor (`parent.constructor gawk`, every var assigned — `sandbox=1`, the rest
`0`/`''`; `program="${1:-}"`; `${inst}_paths` = `"${@:2}"`; `${inst}_progs`,
`${inst}_vnames`, `${inst}_vvals` empty INDEXED arrays via `declare -ga` — the
variables keep insertion order, a repeated NAME replaces its value in place),
destructor order, `kk.call_silent` only, `subshellOk` inherited, registry appends
(`__taw_`; `_progs`, `_vnames`, `_vvals`; only if absent).

### 2.2 buildArgv rc 2 list (nothing runs)

- `cmd` empty; **no program** — `program` empty or all-whitespace-free-empty, every
  `${inst}_progs` element empty, `programFile` empty (empty chunks are skipped, never
  emitted as `-e ''`); `programFile` = `-`.
- a path operand matching `^([A-Za-z_][A-Za-z0-9_]*::)?[A-Za-z_][A-Za-z0-9_]*=` (an
  assignment — the message names `./…`); `inPlace = 1` with no path or with `-`;
  **`inPlace = 1` with `sandbox` ≠ `0`**; `backupSuffix` non-empty with `inPlace = 0`.
- a `setVar` NAME that is not `^[A-Za-z_][A-Za-z0-9_]*$`, or is an awk keyword or
  builtin (`BEGIN END BEGINFILE ENDFILE function func if else while for do break
  continue next nextfile exit return delete getline print printf in` and every
  builtin function name of gawk 5.4), or `ENVIRON`/`PROCINFO`/`SYMTAB`/`FUNCTAB`.
- **the deny-list over the extras**, following gawk's own option parsing on BOTH
  versions: any prefix of a denied long name (`--so`, `--sa`, `--t`… — refuse the
  prefix, never try to decide ambiguity per version), attached short arguments,
  bundles, and **`-W` long options** (the argument of `-W`, attached or the next word,
  goes through the same long-name table). Denied: `-e`/`--source`, `-f`/`--file`,
  `-i`/`--include`, `-l`/`--load`, `-E`/`--exec`, `-F`/`--field-separator`,
  `-S`/`--sandbox`, `-o`/`--pretty-print`, `-g`/`--gen-pot`, `-h`/`--help`/`--usage`,
  `-V`/`--version`, `-C`/`--copyright`, `-d`/`--dump-variables`, `-p`/`--profile`,
  `-D`/`--debug`, `-M`/`--bignum`, and — when `binary`, `nullData` or `inPlace` is on —
  `-P`/`--posix`, `-c`/`--traditional` (they silently disable BINMODE); `--`; any
  extra that is not an option word (it would become THE program), including a bare
  `-`; an argument-taking option as the LAST extra (`-v`, `--assign`, `-W` — a
  dangling one would swallow the next generated word). `-v NAME=…` passes (the
  awk-escape escape hatch of Q2).

### 2.3 `setVar` verbatim through `-v` with an encoding

`setVar NAME VALUE` stores the pair; `buildArgv` emits `-v NAME=enc(VALUE)` where
`enc` doubles every `\`, writes every newline as `\n`, and writes a leading `@` as
`\100`. Measured byte-exact on both versions (a supervisor re-check reproduced every
case, the `\`+newline case needing the `\n` rule). The encoder is written with care:
**the Bash tool collapses `\\` in inline commands** — write it and every probe of it
through a file, and pin the matrix in 005 with `od -c`. No `env`, no prologue.

### 2.4 `nullData` and the binary mode

`nullData == 1` → `-v RS='\0' -v ORS='\0'` (intended awk escapes) and `nul=1` /
`_nulDerived=1` with the P3-F1 guard. `-v BINMODE=3` is emitted when `binary == 1`
OR `inPlace == 1` OR `nullData == 1`; the `binary` property is never written.

### 2.5 The five overridden sinks

As TSed §2.4, keyed on `inPlace == 1`. With `inPlace = 0` and a missing file the
family contract applies with gawk's FATAL semantics: records of the operands BEFORE
the missing one only; count/toArray/toList rc 1 + that count; each rc 1 with RESULT
untouched; first rc 0 + first record + `lastRc` 2 (or, if the missing file is first,
rc 1 with no record).

### 2.6 mapRc and the named deviations

Per Q3. Named deviations (README + kcl README row): (a) a missing input file stops
there — earlier files' records kept with RESULT = count and rc 1; a directory operand
is skipped with a warning and rc 0; (b) the tool's stderr passes through; (c) sandbox
on by default, fail-closed — it also refuses `print > "/dev/stderr"`, input
redirection and `|&`; (d) a program's `exit N` is rc 1 silent (`exit 1`/`exit 2` get
the debug line, worded to say so); (e) `inPlace`/`nullData` derive `BINMODE=3`; (f)
`setVar` is verbatim, unlike `-v`; (g) `print` terminates an unterminated last line;
(h) `programFile` is resolved through AWKPATH (documented; `-` refused).

### 2.7 `TAwk.apply PROGRAM PATH...`

`gawk --sandbox -e PROGRAM -- PATH...` on a throw-away instance
`__taw_a_${BASHPID}_${__TAW_SEQ}`; an empty PROGRAM is **rc 2** (gawk would drop it
and compile the first path as the program); sandbox forced; ≥ 1 path required (rc 2);
an assignment-looking path rc 2; streams; composes with both TPipe forms;
nested-safe.

---

## 3. Pinned facts (tests)

| # | fact | test |
|---|---|---|
| A1 | argv per option singly and combined, byte-exact, in the pinned order; `setVar` after the extras in insertion order; empty chunks never emitted; `--` iff paths; the inplace include as the absolute path | 004 |
| A2 | rc 2 list of §2.2: every deny-list word (short, long, any prefix, attached, bundled, `-W` attached/separate/abbreviated/bundled), `--`, a non-option extra, a bare `-`, a dangling `-v`/`-W`, BINMODE-disabling options only while binary mode is derived; `-v x=1` passes | 004 |
| A3 | every var in `_data` after `new` (`sandbox=1`); `delete` frees `_paths`/`_progs`/`_vnames`/`_vvals`; out-names `__taw_x`, `a_progs`, `a_vnames`, `a_vvals` refused | 004 |
| A4 | `nullData` four-state `nul` sequence; derived `BINMODE=3` with `binary` untouched | 004 |
| A5 | `setVar` verbatim: the §1.1 matrix through `run` and a sink, compared with `od -c`, on both versions; a repeated NAME replaces in place; `clearVars`; an illegal NAME, a keyword, a builtin, `ENVIRON` → rc 2; `setVar` wins over an `addArg -v` of the same name | 005 |
| A6 | each/toArray/count/first/toList vs bare `gawk`; multi-chunk program in order; `-f` + `-e` order; `-F`; an unterminated last line comes out terminated | 005 |
| A7 | a missing file in the middle: only the earlier files' records, per-sink contract, lastRc 2; syntax error rc 1 lastRc 1; `exit 7` → rc 1 silent, lastRc 7; `exit 1` → debug line; a directory → rc 0 with the exact warning; `exit 300` → lastRc 44 | 005 |
| A8 | sandbox: `system()`, `print > f`, `print > "/dev/stderr"`, `"cmd" \| getline`, `getline < f` refused by default (rc 1, lastRc 2, marker files prove nothing ran or was written); `sandbox = 0` runs them; `sandbox = ''`/`yes`/`2` stay sandboxed; `@include` allowed | 005 |
| A9 | CR: text mode strips; `binary = 1` keeps; `inPlace` keeps every CR on disk; `nullData` keeps an embedded CR | 005 |
| A10 | NUL records through the derived `-0` | 005 |
| A11 | inPlace: `sandbox ≠ 0` → rc 2; `run` edits, stdout empty for a plain program; a planted `./inplace.awk` in the cwd is NOT loaded; `backupSuffix = .bak` works on both versions; a missing middle file: earlier files edited, later byte-identical; every sink rc 2 with nothing run | 005 |
| A12 | `TAwk.apply '{print $2}' f` == `gawk --sandbox -e '{print $2}' -- f` in three positions; `apply ''` rc 2; no path rc 2; an assignment-looking path rc 2; nested `apply` keeps the outer instance; `system()` refused | 005 |
| A13 | `set -eu` children through both TPipe forms and `a.each`, guarded sinks; debug switch one line per rc 2 / gawk-error path, silence on rc 0 and on an `exit 7`; D6 + `subshellOk` | 006 |

## 4. Test model

Oracle = bare `gawk` on a fixture tree from `kt_fixture_tmpdir_create` (a 3-line
`a 1`/`b 2`/`c 3` file, a CRLF file, a NUL-separated file with an embedded CRLF, an
unterminated last line, a program file, a name with a space, a name starting with
`-`, files literally named `k=v` and `a::b=v`, a directory). Banner gate first in 005;
message texts compared by prefix except the directory warning (identical on both);
**every child and every probe runs with stdin closed or explicit**; no own `EXIT`
trap; children under `timeout 20`; in-place on copies with `od -c` assertions; the
planted-`inplace.awk` case runs from a `cd` in the test file's own shell.

## 5. Phases

- **P0 — the unit** (gate: 004–006 green on both bashes; the other wrapper suites
  still green on 5.2.37; sweep): `tawk.sh`, tests, README first cut, tutil PLAN §7
  and `tutil/docs/TUtil.md` §4 tawk rows amended.
- **P1 — closeout** (gate: sweep): `bench.sh` (`apply` vs bare `gawk --sandbox -e`,
  interleaved medians ≥ 15, gate 1.5× — the critic measured 1.13–1.26× on a
  prototype), `007_Bench.sh` (10×), README final, `TEST_COVERAGE_NOTES.md`, kcl README
  §2 row (24 → 25), ledger COMPLETE; tutil's stale `TEST_COVERAGE_NOTES.md` refreshed.

  **P1 DONE 2026-09-24** (`<SHA-TA1>`): `bench.sh` rc 0 under `bash -eu` on both
  bashes, gate 2/2 PASS — `apply` 1.18× / 1.17× (10 000-line / one-line file)
  on 5.2.37 + gawk 5.0.0, 1.21× / 1.16× on 5.3.9 + gawk 5.4.0 (medians of 21
  interleaved runs; second runs 1.15×/1.11× and 1.08×/1.19×); the `apply` delta
  ≈4.7 ms (`new` + `sandbox` + `buildArgv` + `delete`), a 1 KiB `setVar`
  encoding ≈0.6 ms per build, zero forks over 33 calls. `tests/007_Bench.sh`
  (12 cases, 10× ceilings); suite **592/592** on both bashes. README final
  (§0 the two gawk versions, §10 Performance), `TEST_COVERAGE_NOTES.md` (592),
  kcl README §2 row (Twenty-five), tutil `TEST_COVERAGE_NOTES.md` refreshed to
  209. Master sweep: run by reviewer.

## 6. Traps (in addition to the tsed and tfind traps)

- Never run gawk without a program and without explicit stdin — it hangs.
- **The Bash tool collapses `\\` in inline commands**: every script that contains a
  backslash (the encoder, its probes, awk programs with escapes) is written to a file.
- A path that looks like `NAME=VALUE` (also `ns::NAME=VALUE`) is an assignment.
- Never emit `-e ''`; a stray non-option word in the options becomes THE program.
- `-W` is a second spelling of every long option.
- `inPlace` needs `sandbox = 0`; load the include by absolute path, never via AWKPATH.
- `INPLACE_SUFFIX` does not exist on gawk 5.0 — use `inplace::suffix`.
- Two gawk versions: compare messages by prefix, pin behaviour, not text.
- A callback that assigns a bare `program=`, `programFile=`, `sandbox=0`,
  `inPlace=` writes the instance's property (measured: `system()` ran on the next
  `run`) — README trap: callbacks declare `local`.
- **Never run `python`** (a leaked `python -` spun a core for 8 days).

## 7. Deliverables

`tawk.sh`, `tests/tests.sh` + `004`–`007`, `bench.sh`, `README.md`,
`TEST_COVERAGE_NOTES.md`, `tawk_ledger.json` COMPLETE, kcl README §2 row, the tutil
PLAN §7 / docs §4 tawk rows, the refreshed tutil `TEST_COVERAGE_NOTES.md`.

## 8. Critic pass (2026-09-23)

| # | sev | finding | landed in |
|---|---|---|---|
| 1 | BLOCKER | `-e ''` is dropped by gawk; with no other program the first path becomes the program (hung on a path `1`) | §1.1, §2.2, §2.7, A1, A12 |
| 2 | MAJOR | `-W long-option` bypasses the deny-list; a dangling `-W` swallows the next generated word | §1.1, §2.2, A2 |
| 3 | MAJOR | a non-option extra becomes THE program (gawk stops parsing at it) | §1.1, §2.2, A2 |
| 4 | MAJOR | `-o -g -h -V -C -d -p -D` skip the program, write files under the sandbox, print to stdout, or hang | §1.1, §2.2 |
| 5 | MAJOR | 5.4 + sandbox + `-M` blanks ARGV[1] and reads stdin; 5.4 sandbox also refuses `ARGV[ARGC++]` | header, §1.1, §2.2 |
| 6 | MAJOR | `-i inplace` resolves through AWKPATH (`.` first): a planted `./inplace.awk` runs with the sandbox off | §1.1, §1.2 (absolute path), A11 |
| 7 | MAJOR | a missing input file is FATAL (later files never read / never edited) | §1.1, §2.5, §2.6, A7, A11 |
| 8 | MAJOR | `-v` with doubled `\` DOES round-trip (plus `@`→`\100`); the env route cost +13–25 ms per run and caused findings 2/10 | §2.0 Q2, §2.3 (env + prologue dropped) |
| 9 | MINOR | an associative `_vars` gave hash order | §2.1 (indexed `_vnames`/`_vvals`) |
| 10 | MINOR | keywords/builtins accepted as setVar names | §2.2, A5 |
| 11 | MINOR | namespaced assignment operands | §1.1, §2.2 |
| 12 | MINOR | the sandbox list was incomplete (`getline <`, `/dev/stderr`, `\|&`, 5.4 ARGV) | §1.1, §2.6(c), A8 |
| 13 | MINOR | in-place traps: `exit` truncates, END goes to stdout, ENDFILE into the file, fatal leaves the file | §1.1 |
| 14 | MINOR | `--posix`/`-P`/`-c`/`--traditional` silently disable BINMODE | §1.1, §2.2 |
| 15 | NIT | `programFile` is resolved through AWKPATH; `-f -` reads stdin | §1.1, §2.2, §2.6(h) |
| 16 | NIT | env-route leftovers | moot (env dropped) |
| 17 | NIT | long-option abbreviations differ between versions | header, §2.2 (refuse any prefix) |
| 18 | NIT | chunks cannot span `-e` words | §1.1, §1.2 |
| 19 | NIT | callback trap must name tawk's properties | §6 |
| 20 | NIT | the directory warning is identical on both versions | §1.1, A7 |

Verified correct by the critic (not to be re-probed): `-e`/`-f` argument-order
concatenation; the rc table incl. `exit -1` → 255; `-v` escapes; `ENVIRON` verbatim
(no msys path conversion); `env` present; `run`'s `command -v` and TPipe with a
multi-word argv; the sandbox's `system`/redirection/pipe/extension refusals;
`inplace::suffix` on both, placed before or after `-i`; CR/BINMODE on file and stdin
input; RS/ORS NUL with `-F`; `print` terminating the last line; the suffix-registry
refusals; `__taw_` has no clash; the 1.5× gate is plausible.
