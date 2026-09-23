# TSed — GNU `sed` wrapper over TUtil (kcl/tsed)

**Status: COMPLETE (P0–P1), 2026-09-23.** P0 (`eafa7f7`) built the unit, the
tests and the `TUTIL_OUT_SUFFIXES` registry (review round 1: `sandbox` fails
closed, `--` on the deny-list); P1 (`<SHA-TS1>`) closed it out (bench, `007`,
README final, `TEST_COVERAGE_NOTES.md`, the kcl README row). **293/293 green on
bash 5.2.37 and on bash 5.3.9**, threaded and (5.2.37) under `--mode single`;
the §5 P1 bench gate passes on both bashes. See §5 for the measured numbers and
[`tsed_ledger.json`](tsed_ledger.json) for the phase record. Planned and
critic-hardened 2026-09-22. Owner: "приступай к
tsed" (2026-09-22). Six design questions answered by the owner (§2.0): four before
the plan, two after the critic pass (§8: 0 blockers, 5 majors, 8 minors, 5 nits —
all folded in below). Fourth wrapper after tgrep, thead, ttail, tfind; everything
those units settled applies (the tgrep constructor rule, every var assigned,
`kk.call_silent`, `_nulDerived` with the P3-F1 guard, the rc-preserving override
spelling, the one-liner on a unique throw-away instance, the named deviations,
D6/`subshellOk`, the `TUTIL_OUT_PREFIXES` registry). Read first: `kcl/tfind/PLAN.md`
(§2, §6, §8) and `kcl/thead/PLAN.md` (§6, §8), `kcl/tfind/tfind.sh`,
`kcl/ttail/ttail.sh` (the overridden-sink spelling), `kcl/tutil/README.md` "Writing
a descendant".

**Source of truth:** GNU sed 4.9. Under bash 5.2.37 `sed` resolves to Git for
Windows' `C:\bin\Git\usr\bin\sed.exe`, under 5.3.9 to `C:\bin\msys64\usr\bin\sed.exe`
— two binaries, both 4.9, byte-identical in every probe. D4: GNU dialect,
PATH-resolved binary, banner gate in the behavioural tests (`sed (GNU sed) `).
**Base:** `TSed : TUtil`. **Ledger:** `kcl/tsed/tsed_ledger.json`. **Prefix:**
`__tsd_` (`__ts_` is thashset's, not a tutil descendant; no clash anywhere in kcl),
appended to `TUTIL_OUT_PREFIXES` at load. No `static var`. Sources
`../tutil/tutil.sh` only.

---

## 1. Scoping

### 1.1 The tool, measured (sed 4.9, both bashes)

| probe | result |
|---|---|
| option order | **each `-e` is compiled when it is read**, with the flags known so far: `sed -E -e 's/(/X/'` is rc 1 ("Unmatched ( or \("), `sed -e 's/(/X/' -E` silently runs the expression as BRE (rc 0); `sed -e 's/(a)1/[\1]/' -E` is rc 1 ("invalid reference \1"). Every option must precede the first `-e` |
| `--` | ends the options; `sed -e EXPR -- -weird` reads the file `-weird`; `sed -- -e 's/a/A/' f` takes `-e` as the SCRIPT (rc 1 "unknown command `-'") |
| no script | `sed FILE` takes FILE as the script (`unknown command: 'f'`, rc 1); `sed -e '' f` is the identity; `:` alone is a label error, `b` is a no-op command |
| several `-e` | joined with newlines into one script: `-e '1{' -e 's/a/J/' -e '}'` works; an expression may itself contain a newline; `#n` as the first line of the first chunk forces `-n`; an expression ending in `a\` swallows the next chunk (even a `-f` script) as text |
| `-f FILE`, `-f -` | script from a file / from stdin; a missing FILE is **rc 4** (`couldn't open file`) |
| rc | `0` ok; **`1`** bad script; **`2`** a missing input file — the OTHER files are still processed and printed (partial); **`4`** an I/O error — a directory operand, a missing `-f` script, a failed backup rename — processing STOPS at that operand (earlier output kept, later files never read / never edited); **`q N` / `Q N`** exit with N mod 256 (`2q7` → 7 after two lines, `q256` → 0, `q257` → 1); a script's `q1`/`q2`/`q4` is indistinguishable from sed's own error codes |
| CR | text mode strips the CR on input **and writes LF**: `sed -i -e ''` (the identity) rewrites every CRLF line ending of the file to LF; `-b` keeps the CR on input and output; under `-z` an embedded CR inside a NUL record is stripped too (`a\r\nb` → `a\nb`) unless `-b` |
| `-z` | NUL-separated input and output records; an unterminated last NUL record stays unterminated |
| last line without `\n` | kept without `\n` |
| several files | ONE stream by default (`$` = last line of the last file); `-s` makes them separate; **`-i` implies `-s`** |
| `-n` | no auto-print; with no `p` there are zero records |
| `-i[SUFFIX]` | in-place: writes nothing to stdout; suffix ATTACHED (`-i.bak` ≡ `--in-place=.bak`); a space or a leading `-` in the suffix is harmless (one argv word); **`*` in the suffix is replaced by the OPERAND AS GIVEN**, not its base name (`bak_*` on `f.txt` → `bak_f.txt`, but on `p/k.txt` → `bak_p/k.txt`, i.e. a directory `bak_p/` that must exist, else rc 4 with the file untouched — measured at P0; `*` alone = no backup at all, silently); **`/` is a directory** (`bk/*` writes into `bk/`, a missing directory is rc 4 with the file untouched); `-i` with no file is "no input files"; `-i` on `-` is "can't read -" (rc 2); `-i` + `q N` / `Q` / `-n` without `p` **truncates the file** silently |
| `e`, `s///e`, `r`, `R`, `w`, `W`, `s///w FILE` | execute a shell command / read / write arbitrary files; `--sandbox` refuses all of them at compile time (rc 1, no output, no partial processing — even in a later `-e` or inside a `-f` script, even with `-i`); the common idiom `s/a/A/w /dev/stdout` is refused too (use `p`). `--sandbox` does NOT refuse `-i` — it limits the script, not in-place writes. `F`, `=`, `l` are allowed and print to stdout (they arrive as records; `F` prints `-` for stdin) |
| `--debug` | prints `SED PROGRAM:` / `INPUT:` / `PATTERN:` lines to STDOUT, interleaved with the data |
| stdin | no file operand → stdin; `-- -` = stdin explicitly |
| stderr | the tool's own diagnostics are unconditional and locale-quoted |

### 1.2 Surface

```bash
class TSed : TUtil
    public
        var expr            # the FIRST expression (-e); '' = none (the identity is addExpr '')
        var scriptFile      # -f FILE ('' = off), emitted after the expressions
        var extended        # -E
        var quiet           # -n
        var separate        # -s   (implied by -i; inert under inPlace)
        var nullData        # -z → derives the sinks' -0 AND -b (§2.3, §2.5)
        var binary          # -b  (keep the CR; also derived, §2.5)
        var sandbox         # --sandbox, DEFAULT 1 (owner Q1)
        var inPlace         # -i  (derives -b; sinks refused; §2.4, §2.5)
        var backupSuffix    # -iSUFFIX (only with inPlace = 1; §2.2)
        var _nulDerived
        constructor Create  # [EXPR [PATH...]] — EXPR → expr; assigns EVERY var; parent.constructor sed
        destructor  Destroy # frees ${inst}_paths and ${inst}_exprs, then inherited
        proc paths          # PATH... replaces the operand list ('' list = stdin)
        proc addExpr        # EXPR... appended to ${inst}_exprs (after `expr`); '' is a real element (the identity)
        proc clearExprs     # empties ${inst}_exprs (not `expr`)
        override func buildArgv   # sed [--sandbox] [-E] [-n] [-s] [-z] [-b] [-i[SFX]] [extras] [-e expr] [-e X...] [-f F] [-- PATH...]
        override func mapRc       # 0→0; 1,2,4 → 1 + debug; 127 base; any other (q/Q) → 1 silent
        override proc each        # inPlace = 1 or --debug in the extras → rc 2, nothing runs; else inherited
        override func toArray     # same (rc-preserving spelling)
        override func toList      # same
        override func first       # same
        override func count       # same
        static proc edit          # TSed.edit EXPR PATH... → `sed --sandbox -e EXPR -- PATH...` stream; ≥1 path required
end
```

argv shape, pinned: `sed` `[--sandbox]` `[-E]` `[-n]` `[-s]` `[-z]` `[-b]`
`[-i[SUFFIX]]` `[EXTRA OPTIONS from addArg]` `[-e EXPR]` `[-e X ...]` `[-f FILE]`
`[-- PATH...]` — every option before the first `-e` (§1.1), `--` only with ≥ 1 path,
`-b` emitted when `binary = 1` OR derived (§2.5).

### 1.3 Not in scope

1. BSD sed (D4). 2. `-i` on a symlink / across devices: tool behaviour, not modelled.
3. `--posix`, `-u`, `-l N`, `--follow-symlinks`, `--debug` pass through `addArg`
   (the deny-list of §2.2 does not name them); `--debug` is usable with `run` only.

---

## 2. Design decisions

### 2.0 Owner decisions (2026-09-22)

| Q | decision |
|---|---|
| Q1 sandbox | `sandbox = 1` by default and **fail-closed**: `--sandbox` is omitted only when `sandbox` is exactly `0` (every other value keeps it — a deliberate exception to the family boolean rule, P0 review): `e`, `s///e`, `r`, `R`, `w`, `W`, `s///w` are refused by sed itself (rc 1, its own message). A caller who needs them sets `s.sandbox = 0` explicitly. Named deviation from tool parity |
| Q2 expressions | BOTH `var expr` (the common case, the constructor's first argument) and `proc addExpr` / `proc clearExprs` over `${inst}_exprs`; `expr` is emitted first, then the list in order; plus `var scriptFile` for `-f` |
| Q3 rc | `0→0`; `1`, `2`, `4` → rc 1 + one `kk.debug` line worded "sed exited N (a sed error, or the script's q/Q N)"; `127` keeps the base wording; any other status (a script's `q N`/`Q N`) → rc 1 **silent**, the raw value in `lastRc` |
| Q4 in-place | `inPlace` + `backupSuffix`; `run` works; the five sinks are overridden and answer rc 2 when `inPlace = 1` |
| Q5 CRLF (after the critic) | `inPlace = 1` and `nullData = 1` **derive `-b`**: in text mode sed rewrites CRLF to LF on disk (even the identity) and strips a CR inside a NUL record. The derivation lives in buildArgv only (`-b` emitted when `binary == 1` OR `inPlace == 1` OR `nullData == 1`); the `binary` property is never written, so no bookkeeping flag is needed. On LF-only files `-b` changes nothing. Named deviation |
| Q6 extras (after the critic) | a **deny-list** in `buildArgv` that follows sed's own option parsing (P0: unambiguous long-option abbreviations such as `--in=`, `--expr=`, `--null`, `--sand` and attached short arguments such as `-i.bak`, `-es/a/b/` are the same options and are refused too; `--` in the extras is refused because it would turn the expressions into operands): an extra that duplicates a typed property or breaks the record stream is rc 2 with a message naming the property to use — `-i`/`--in-place[=…]`, `-z`/`--null-data`, `-e`/`--expression[=…]`, `-f`/`--file[=…]`, `-n`/`--quiet`/`--silent`, `-s`/`--separate`, `-E`/`-r`/`--regexp-extended`, `-b`/`--binary`, `--sandbox`, and any bundled short-option word containing one of `i z e f n s E r b` (`-ni`, `-nE`); everything else (`--posix`, `-u`, `-l N`, `--follow-symlinks`, `--debug`) passes |

### 2.1 Everything the family decided applies verbatim

Constructor (`parent.constructor sed`, every var assigned — `sandbox=1`, the rest
`0`/`''`; `expr="${1:-}"`; `${inst}_paths` = `"${@:2}"`; `${inst}_exprs` = empty,
both via `declare -ga`), destructor order, `kk.call_silent` only, `subshellOk`
inherited, the prefix registry append (`__tsd_`, only if absent).

**`${inst}_exprs` as an out-name.** `tutil._badOut` refuses only `_args`, `_argv`,
`_paths`; measured, `s.toArray s_exprs` turns the records into the next run's
script (and with `sandbox = 0` a data line `e …` becomes a command). P0 turns the
suffix list into a second registry, `TUTIL_OUT_SUFFIXES=(_args _argv _paths)`,
with the same two guards as `TUTIL_OUT_PREFIXES` (its own name refused as an
out-name; empty or non-array refuses every name); `tsed.sh` appends `_exprs` at load
(only if absent). tutil 001 gains the cases; the tutil README "writing a
descendant" names both registries.

### 2.2 buildArgv rc 2 list (nothing runs)

`cmd` empty; **no script at all** (`expr` empty, `${inst}_exprs` empty and
`scriptFile` empty — sed would take the first path as the script); `inPlace = 1`
with no path, or with the path `-`; `backupSuffix` non-empty with `inPlace = 0`;
`backupSuffix` equal to `*` (the backup name would equal the file name: no backup,
silently); an extra on the Q6 deny-list. An empty element inside `${inst}_exprs` is
allowed (sed's identity). A suffix containing `*` (the operand as given — with a directory in the operand it names a backup DIRECTORY) or `/`
(a directory; missing → the tool's rc 4) is passed and documented. No expression
text is validated by the wrapper — sed compiles it.

### 2.3 `nullData` derives `-0`

`nullData == 1` → `nul=1`, `_nulDerived=1` unless `nul` was already 1 (P3-F1
guard); undone when `nullData` goes back to 0. sed has no headers, so no multi-path
exception. `nullData` also derives `-b` (§2.5).

### 2.4 The five overridden sinks

`inPlace == 1` → `kk.debug "Error: TSed.<sink>: in-place editing writes nothing to
stdout; use run"`, rc 2, nothing runs, `_lastRc` untouched; `--debug` in the extras
→ the same with "sed --debug writes to stdout; use run". Funcs: `kk._return "";
return 2`. Otherwise the rc-preserving spelling of thead §6 / ttail §2.1: `inherited X
"$@" || rc=$?; n="$RESULT"; kk._return "$n"; return "$rc"` for the four funcs; the
proc `each`: `inherited each "$@" || rc=$?; return "$rc"` (verified by the critic:
rc preserved, the callback's frame, `__TPIPE_QUIET`, D6 and `this` identical to the
base, no measurable per-record cost). Pinned with `inPlace = 0` and a missing file
(the family contract, NOT "every sink rc 1 + count"): `count`/`toArray`/`toList` →
rc 1 with the real count; `each` → rc 1, RESULT untouched (a proc); `first` → rc 0,
the first record, `lastRc` 2, no debug line (TUtil's consumer-stop contract).

### 2.5 CRLF, `binary`, and the derived `-b`

Text mode strips the CR on input and writes LF, so `crlf` is a no-op for the stream
(as in tgrep §2.6). `buildArgv` emits `-b` when `binary == 1` OR `inPlace == 1` OR
`nullData == 1` (owner Q5); it never writes the `binary` property, so there is no
bookkeeping and nothing to undo — turning `inPlace` off takes the derived `-b` away
on the next build. Consequence, documented: the wrapper has NO text-mode in-place
path (a caller who wants CRLF→LF conversion does it explicitly in the script,
`s/\r$//`, which works under `-b`). `binary = 1` + `crlf = 1` strips exactly one CR
per record when the script does not append after `$`.

### 2.6 mapRc and the named deviations

Per Q3. Named deviations (README + kcl README row): (a) a missing input file among
good ones keeps the other files' records with RESULT = count and rc 1 (rc 2 in
`lastRc`); an I/O error (rc 4) stops at that operand, earlier records kept; (b) the
tool's own stderr passes through unconditionally; (c) `sandbox = 1` by default (Q1);
(d) a script's `q N`/`Q N` status is not an error — rc 1 silent, raw in `lastRc`
(a `q1`/`q2`/`q4` gets the debug line, worded to say so); (e) `inPlace`/`nullData`
derive `-b` (Q5).

### 2.7 `TSed.edit EXPR PATH...`

Static one-liner: `sed --sandbox -e EXPR -- PATH...` on a throw-away instance
`__tsd_e_${BASHPID}_${__TSD_SEQ}` created with an EMPTY `expr` and then
`addExpr "$EXPR"`, so an empty EXPR is a real element — the identity (pinned
against `sed --sandbox -e '' -- f`); sandbox forced on, no way to turn it off from
the one-liner; ≥ 1 path required (rc 2 — with none sed reads the caller's stdin);
streams; composes with both TPipe forms; nested-safe.

---

## 3. Pinned facts (tests)

| # | fact | test |
|---|---|---|
| S1 | argv per option singly and combined, byte-exact, every option before the first `-e`; `expr` first then `addExpr` items in order; `-f` after the expressions; `--` iff paths; extras after the typed options and before the expressions; `${s}_args` empty after `new s EXPR PATH` | 004 |
| S2 | rc 2 list of §2.2 incl. every Q6 deny-list word, bundled `-ni`, long forms with `=` — RESULT '', nothing runs, `${inst}_argv` empty, one debug line; `--posix`, `-u`, `-l 40`, `--debug` pass | 004 |
| S3 | every var in `_data` after `new` (incl. `sandbox=1`, inherited `subshellOk`); `delete` frees `_paths`/`_exprs`; `s.argv __tsd_v` → rc 2; `s.toArray s_exprs` and `s.argv s_exprs` → rc 2 (suffix registry) with the exprs intact; `TUTIL_OUT_SUFFIXES` refused as a name | 004 |
| S4 | `nullData` four-state `nul` sequence; the derived `-b` for `inPlace`/`nullData` (argv shows `-b`, the `binary` property stays 0, and the `-b` disappears when `inPlace`/`nullData` go back to 0) | 004 |
| S5 | `extended = 1` + `expr = 's/(a)1/[\1]/'` on the input `a1` → `[a]`; the argv pin proves `-E` always precedes the first `-e` | 004/005 |
| S6 | each/toArray/count/first/toList vs bare `sed` on the fixture; multi-`-e` block; `-f` script; `-n` + `p`; `-s` vs default `$`; unterminated last line; `addExpr ''` is the identity | 005 |
| S7 | missing file among good ones: per §2.4's contract (count/toArray/toList rc 1 + real count, each rc 1, first rc 0 + record + lastRc 2); a directory operand lastRc 4 and the later file NOT read; a missing `-f` script lastRc 4; bad script rc 1 lastRc 1; `2q7` → rc 1 silent, lastRc 7, the two lines delivered; `2q1` → rc 1 with the debug line | 005 |
| S8 | sandbox: `s///e`, `e`, `w FILE`, `s///w /dev/stdout` and a `-f` script with `w` refused by default (rc 1, lastRc 1, a marker file proves nothing ran or was written); `sandbox = 0` runs them | 005 |
| S9 | CR: text mode strips; `binary = 1` keeps; `binary = 1` + `crlf = 1` strips exactly one; `inPlace = 1` on a CRLF file keeps every CR on disk (derived `-b`); `nullData = 1` keeps an embedded CR | 005 |
| S10 | `-z` NUL records through the derived `-0`; unterminated last NUL record | 005 |
| S11 | inPlace: `run` edits the file, stdout empty; `backupSuffix = .bak` keeps the backup; `bak_*` names it by base name; `*` alone is rc 2; a missing backup dir is rc 1 / lastRc 4 with the file untouched; every sink rc 2 with nothing run (file byte-identical, `_lastRc` still -1); `inPlace` + a directory before a good file: the good file NOT edited (rc 4 stops) | 005 |
| S12 | `TSed.edit 's/a/A/' f` == `sed --sandbox -e 's/a/A/' -- f` in three positions; `edit '' f` == the identity; no path rc 2; nested `edit` from an `each` callback keeps the outer instance; `edit` with `s///e` refused | 005 |
| S13 | `set -eu` children through both TPipe forms and `s.each`, every sink call guarded; debug switch one line per rc 2 / sed-error path, silence on rc 0 and on a `q N` status (N ∉ {1,2,4,127}); D6 warning + `subshellOk` | 006 |

## 4. Test model

Oracle = bare `sed` on a fixture tree from `kt_fixture_tmpdir_create`: a 3-line file
(`a1 b2 c3`), a CRLF file, a NUL-separated file (one record with an embedded CRLF),
an unterminated last line, a script file, a name with a space, a name starting with
`-`, a directory. Banner gate first in 005; no own `EXIT` trap; children under
`timeout 20`; the tool's stderr matched by prefix; in-place cases work on copies made
inside `_KT_TMPDIR` and assert the bytes (`od -c`) afterwards. Files: `004_Argv.sh`,
`005_Run.sh`, `006_Contract.sh`, `tests.sh`.

## 5. Phases

- **P0 — the unit** (gate: 004–006 green on both bashes; tutil/tgrep/thead/ttail/
  tfind still green on 5.2.37; sweep): `tsed.sh`, tests, README first cut, the
  `TUTIL_OUT_SUFFIXES` registry in tutil (+ 001 cases + README note), the tsed rows in
  tutil PLAN §7 AND `tutil/docs/TUtil.md` §4 amended to the owner's decisions.
- **P1 — closeout** (gate: sweep): `bench.sh` (`edit` vs bare `sed -e`, interleaved
  medians ≥ 15, gate 1.5×, clock `TStopwatch.getTimeStamp`), `tests/007_Bench.sh`
  (10× ceiling), README final, `TEST_COVERAGE_NOTES.md`, kcl README §2 row (23 →
  24), ledger COMPLETE.

**P1 DONE 2026-09-23.** `bench.sh` (459 lines), `tests/007_Bench.sh` (427 lines,
11 cases), `TEST_COVERAGE_NOTES.md` (293 rows), README final (§0 the owner
decisions, §9 Tests, §10 Performance), the kcl README row + Twenty-three →
Twenty-four, ledger COMPLETE. Suite **293/293** on both bashes (threaded) and
under `--mode single` on 5.2.37.

Measured on an idle box, medians of NR = 21 **interleaved** runs, both bashes:

| | bash 5.2.37 | bash 5.3.9 |
|---|---|---|
| `buildArgv` / `argv NAME` (10 words, one extra scanned) | 1105.8 / 1979.8 µs | 1170.7 / 2062.1 µs |
| `buildArgv` **refused** (rc 2, deny-list `-ni` after `-u --posix`) | 1149.3 µs | 1210.5 µs |
| **`new` + `addExpr` + `sandbox` + `argv` + `delete`** (the `edit` delta) | **5414.4 µs** | **5112.1 µs** |
| bare `sed --sandbox -e 's/a/A/' --` (10 000 lines) → `TSed.edit` | 37.20 → 43.25 ms = **1.16×** | 36.44 → 43.23 ms = **1.18×** |
| bare `sed --sandbox -e 's/a/A/' --` (1 line) → `TSed.edit` | 33.67 → 40.56 ms = **1.20×** | 31.08 → 38.78 ms = **1.24×** |
| `s.count` (10 000 recs) vs `sed … \| wc -l` | 480.39 / 50.83 ms = 9.45× | 482.30 / 47.05 ms = 10.24× |
| marginal cost of one record read into bash | ~44 µs | ~44 µs |

Gate **1.5×: 2/2 PASS on both bashes**; a second 5.2.37 run read 1.14× / 1.18×.
The fixed delta is ~5.1–5.4 ms (eleven properties and two arrays, against
tfind's nine and one at ~4.7 ms); the gate rows' own delta is 6.1–7.7 ms, the
rest being `run`'s `command -v` probe and `mapRc` dispatch. The interleaved-median
protocol was needed again: the **worst single pairing** inside these samples read
8.49× / 12.31× on 5.2.37 and 9.12× / 9.34× on 5.3.9, and the means ran up to 2.2×
the medians. The `count` row is published, never gated: at 10 000 records the
`wc -l` pipeline wins by ~10×, while at 200 (`tests/007_Bench.sh`) the sink's
cheaper fixed half puts it slightly ahead.

## 6. Traps (in addition to tutil PLAN §6, thead §6, tfind §6)

- Every option before the first `-e` (§1.1); the Q6 deny-list keeps expressions and
  flags out of `addArg`.
- No script ⇒ rc 2; never let sed read the first path as the script. `expr = ''`
  means none; the identity is `addExpr ''`.
- `-i` takes its suffix ATTACHED; `*` = base name, `/` = directory.
- Under `inPlace`, `q`/`Q`/`quiet` without `p` truncate the file — README trap.
- The overridden sinks use the rc-preserving spelling; the proc `each` too.
- A callback that assigns a bare `expr=`, `quiet=`, `sandbox=0`, `inPlace=` writes the
  INSTANCE's property (dynamic scoping) — a bare `sandbox=0` silently disarms the
  security default for the next run. README trap: callbacks declare `local`.
- In-place tests edit copies; assert the original bytes after every refused sink.
- CR fixtures through `printf`, never an array literal.

## 7. Deliverables

`tsed.sh`, `tests/tests.sh` + `004`–`007`, `bench.sh`, `README.md`,
`TEST_COVERAGE_NOTES.md`, `tsed_ledger.json` COMPLETE, kcl README §2 row, the
`TUTIL_OUT_SUFFIXES` registry + tutil 001 cases + README note, the tutil PLAN §7 and
`tutil/docs/TUtil.md` §4 tsed rows.

## 8. Critic pass (2026-09-22)

An Opus critic reviewed the first draft with 9 probe scripts and a prototype on
both bashes (every output byte-identical):

| # | sev | finding | landed in |
|---|---|---|---|
| 1 | MAJOR | in-place in text mode rewrites CRLF to LF on disk (even the identity) | owner Q5 → derived `-b`, §2.5, S9 |
| 2 | MAJOR | `addArg -i`/`-ni`/`-z`/`--expression`/`-f` bypass the typed properties (a sink edits or truncates the file, loses records, reorders the script) | owner Q6 → deny-list, §2.2, S2 |
| 3 | MAJOR | `${inst}_exprs` fillable as an out-name (records become the next script) | §2.1 `TUTIL_OUT_SUFFIXES`, S3 |
| 4 | MAJOR | `TSed.edit ''` could not be the identity (`expr=''` = none) | §2.7 (addExpr), S12 |
| 5 | MAJOR | the missing-file pin was wrong for `each` (proc) and `first` (consumer-stop) | §2.4, S7 |
| 6 | MINOR | rc 4 stops processing (not partial like rc 2); a missing `-f` script is rc 4 | §1.1, §2.6(a), S7, S11 |
| 7 | MINOR | the suffix rule targeted harmless characters; `*` and `/` are the real ones | §1.1, §2.2, S11 |
| 8 | MINOR | a `q1/q2/q4` looks like a sed error; `-i` + `q`/`-n` truncates silently | §2.0 Q3 wording, §2.6(d), §6 |
| 9 | MINOR | the sandbox list lacked `s///w` (incl. `/dev/stdout`); sandbox does not guard `-i` | §1.1, S8 |
| 10 | MINOR | `-z` in text mode strips a CR inside a record | owner Q5, §2.5, S9 |
| 11 | MINOR | `--debug` prints to stdout (records) | §1.3, §2.4 |
| 12 | MINOR | a callback's bare assignment writes the instance's properties (`sandbox=0`!) | §6 |
| 13 | MINOR | `tutil/docs/TUtil.md` §4 carries the same stale tsed row as PLAN §7 | §5 P0, §7 |
| 14 | NIT | `#n` and `a\` interact across chunks | §1.1 |
| 15 | NIT | `inPlace` with the path `-` | §2.2 |
| 16 | NIT | two different sed binaries (Git for Windows / msys64), both 4.9 | header |
| 17 | NIT | S5 needs `a1` input; S9's crlf rule holds only without an append after `$` | S5, S9, §2.5 |
| 18 | NIT | `-i` implies `-s` | §1.1, §1.2 |

Verified correct by the critic (not to be re-probed): `override proc each` keeps rc,
the callback's frame, `__TPIPE_QUIET`, D6, `this` and costs nothing per record; the
refusal leaves `_lastRc` -1 and the file byte-identical; `first` with zero records is
rc 1; guarded sinks under `set -eu`; the sandbox is compile-time and total (later
`-e`, `-f`, `-i`), works with `--posix`; the option-order, `--`, no-script, identity,
multi-`-e`, rc 2 partial, `q N` mod 256, unterminated-line, `-z`/`-s`, `-i` stdout,
CR/`-b` claims; nested `edit`; `__tsd_` registry append and refusal; the banner;
in-place works on NTFS `/tmp`.
