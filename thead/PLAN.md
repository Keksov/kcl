# THead — GNU `head` wrapper over TUtil (kcl/thead)

**Status: COMPLETE (P0–P1).** P0 DONE 2026-09-15 (unit + tests + README first cut;
two plan facts corrected at P0, see §2.4/§2.5); **P1 DONE 2026-09-16** (bench.sh,
tests/007_Bench.sh, README final, TEST_COVERAGE_NOTES.md, kcl README §2 row,
ledger COMPLETE) — the numbers are under §5. Owner: "приступай к
ttail и thead" (2026-09-15). A critic pass (§8) found 3 blockers and 5 majors in
the first draft; every one is folded into the sections below. Sibling:
[`kcl/ttail/PLAN.md`](../ttail/PLAN.md) — the two units are written together, by one
worker per phase, and share every decision below unless the ttail plan says
otherwise.

**Source of truth:** GNU coreutils 8.32 `head` as shipped by MSYS2 (D4 of the tpipe
plan: GNU dialect, PATH-resolved binary, GNU banner gate in the behavioural tests).
Measured 2026-09-15 on bash 5.2.37 and 5.3.9 (`/usr/bin/head` first on PATH under
both, no non-GNU shadow): §1.1.
**Base:** [`kcl/tutil`](../tutil/README.md) — `THead : TUtil`, the tobjectlist→tlist
sourcing pattern, exactly as [`kcl/tgrep`](../tgrep/README.md) does it. Read first:
the header block of `kcl/tgrep/tgrep.sh` and `kcl/tgrep/README.md` (the constructor
rule `parent.constructor grep` — never `inherited` in a constructor; every var
assigned; `kk.call_silent`; `_nulDerived` with the P3-F1 guard; the throw-away
instance name of the static one-liner), `kcl/tgrep/tests/004_Argv.sh` §G (the
four-state `_nulDerived` sequence), `kcl/tutil/README.md` "Writing a descendant".
**Template:** tutil PLAN §7 (thead row — amended by this plan, §2.9) and
`tutil/docs/TUtil.md` §4.
**Ledger:** `kcl/thead/thead_ledger.json`. **Prefix:** `__th_` (registered in
`tutil._badOut`, §2.8). No `static var`. Nothing is shared between the two units but
the plan text: `thead.sh` sources `../tutil/tutil.sh` **only**, and the common
`buildArgv` shape is duplicated in `ttail.sh` on purpose (kcl README: one unit per
directory, its own tests, its own ledger).
**Workflow / conventions:** as tpipe/tutil (supervisor mode, red-first, dual-bash,
sweep, gated commits, kcl README §1 in full).

---

## 1. Scoping

### 1.1 The tool, measured (coreutils 8.32, both bashes)

| probe | result |
|---|---|
| rc | `0` ok; **`1`** for everything else: missing file, a directory operand, a bad or overflowing `-n` value, an unknown option, **and a partial failure that still printed output** (`head -n 1 a missing` prints a's line, rc 1). Never rc 2 |
| `-n N` | `-n 08` = 8 (decimal, also on an 11-line file); `-n -2` = all but the last 2 lines; `-n +3` = 3; **`-n -0` = everything** ("all but the last 0"), `-n 0` and `-n +0` = nothing; `-n 1K` accepted (suffix); `-n 99999999999999999999` → rc 1 "Value too large" |
| `-c N` | bytes, same forms: `-c -0` = everything, `-c +0` = nothing, `-c -2` = all but the last 2 bytes |
| several files | `\n==> NAME <==\n` is emitted **before every operand after the first** (the first file gets `==> NAME <==\n` with no leading `\n`) — **as records through the sinks**: the leading `\n` is an empty record only when the previous file's last line was terminated; an unterminated previous file gives one record fewer. `-q` suppresses the headers, `-v` forces them even for one file; `-q -v` and `-v -q` are accepted silently, last flag wins |
| `-z` | **re-delimits the INPUT by NUL** (a text file is ONE record, so `-n N` for any N ≥ 1 is the whole file) and NUL-terminates the output records — except the headers and the inter-file separator, which stay `\n`-terminated under `-z` too; an unterminated last input record stays unterminated on output |
| last flag wins | `-n 3 -n 5` = 5; `-n 1 -c 2` = the `-c`; `-c 2 -n 1` = the `-n` |
| CR | **kept** (`head`/`tail` are byte tools — unlike grep/sed/gawk, tutil PLAN §2.6) |
| last record without `\n` | delivered as is |
| stdin | no operand → stdin; `-- -` = stdin explicitly |
| `--` | terminates options; `-- -weird` and `-- ./-weird` work |
| stderr | the tool's own diagnostics are unconditional and their quoting depends on the locale (`'…'` under C, `‘…’` under the unit's `C.UTF-8` self-heal) |

### 1.2 Surface

```bash
class THead : TUtil
    public
        var lines           # -n N   ('' = off). N = [+-]?digits, ≤ 19 digits (§2.2); '' and bytes '' → tool default (10 lines)
        var bytes           # -c N   ('' = off); lines and bytes both set → rc 2
        var quiet           # -q  never print file-name headers
        var verbose         # -v  always print them; quiet and verbose both 1 → rc 2
        var zeroTerminated  # -z  NUL records → derives the sinks' -0 (§2.3); with ≥ 2 paths or verbose = 1 → rc 2
        var _nulDerived     # private bookkeeping (tgrep shape, P3-F1 guard)
        constructor Create  # [N [PATH...]] — N goes to `lines`; assigns EVERY var; parent.constructor head
        destructor  Destroy # frees ${inst}_paths, then inherited
        proc paths          # PATH... replaces the operand list ('' list = stdin)
        override func buildArgv   # head [-q|-v] [-z] [-n N | -c N] [extras] [-- PATH...]
        override func mapRc       # 0→0; 1→1 + one debug line (head has no "answer" rc)
        static proc take          # THead.take N PATH... → stream (`head -n N -- PATH...`); ≥1 path required
end
```

Reserved by TUtil (never a `var` here): `cmd crlf nul _lastRc subshellOk buildArgv
addArg clearArgs argv run each toArray toList first count lastRc mapRc`; kklass:
`property call parent delete`. `lines`/`bytes` are free (tutil PLAN §1.2 named them
as the head/tail choice on purpose).

argv shape, pinned: `head` `[-q|-v]` `[-z]` `[-n N | -c N]` `[EXTRA ARGS from addArg]`
`[-- PATH...]` — `--` only with ≥1 path.

### 1.3 Not in scope

1. Suffix multipliers (`-n 1K`, `-c 2M`): refused by the regex (rc 2); `addArg -n 1K` is
   the escape hatch — and because extras come **last** and head is last-flag-wins, an
   `addArg -n`/`-c` **replaces** `lines`/`bytes` (even switching the mode) in silence.
   That is the documented escape hatch, pinned in 004.
2. BSD/macOS dialects (D4). 3. Anything else in `head --help`: `addArg`.

---

## 2. Design decisions

### 2.1 Everything tgrep already decided applies verbatim

Constructor (`parent.constructor head`, all vars assigned, `${inst}_paths` via
`declare -ga`), destructor order, `kk.call_silent` only, ordered sink tails come from
TUtil untouched, `tutil._badOut` refuses `${inst}_paths`, `subshellOk` is inherited
and not redeclared, the static one-liner uses `__th_t_${BASHPID}_${__TH_SEQ}`.

### 2.2 The count value

`lines`/`bytes` are validated with ONE regex, `^[+-]?[0-9]+$`, **plus a magnitude
guard**: at most 19 digits (the int64 bound `kk.isInt` uses — without `kk.isInt`
itself, which would strip the sign and turn `-0`/`+0` into `0`), and passed
**verbatim** (`-n 08` → 8 is head's own decimal reading, pinned). Empty string = the
option is not emitted (head's default of 10). A value that fails the regex or the
guard is rc 2 at buildArgv, nothing runs. `lines` and `bytes` both non-empty → rc 2
(head would take the last one). The sign table, pinned behaviourally in 005 and
carried as a table in the README:

| value | head `-n`/`-c` | tail `-n`/`-c` (ttail) |
|---|---|---|
| `N` | first N | last N |
| `+N` | first N (same as `N`) | **from the N-th** (`+2` = skip the first line) |
| `-N` | **all but the last N** | last N (same as `N`) |
| `0`, `+0` | nothing | `0`/`-0` nothing, `+0` everything |
| `-0` | **everything** | nothing |

### 2.3 `zeroTerminated` derives `-0` — for one path only

`-z` re-delimits the *input* and NUL-terminates the output records, but the
`==> NAME <==` headers and the separator stay `\n`-terminated under `-z` (measured),
so with two operands a derived `-0` frames header + data into ONE record.
`zeroTerminated = 1` together with **more than one path, or with `verbose = 1`**, is
therefore **rc 2 at buildArgv**, nothing runs. With one path (or stdin) the
derivation is tgrep §2.7's with its P3-F1 guard: `zeroTerminated == 1` → `nul=1`
and `_nulDerived=1` unless `nul` was already 1 (caller-set, never claimed); undone
when `zeroTerminated` goes back to 0 (the four-state sequence of tgrep 004 §G). A
text file under `-z` is one record for any `-n N ≥ 1`; an unterminated last NUL
record is delivered by TPipe's `|| [[ -n ]]` tail (pinned, H10).

### 2.4 Headers are records

With two or more paths and neither `-q` nor `-v`, head emits `\n==> NAME <==\n`
before every operand after the first; through the sinks those are ordinary records
(`count` counts them; `first` on two files returns `==> FIRST <==`). The empty
record exists only when the previous file's last line was terminated: two
terminated 3-line files under `-n 5` are 9 records, the same pair with the first
file unterminated is **8** (the separator's leading `\n` terminates the previous
file's last line instead of standing alone; measured at P0 — the critic's "7" was
off by one) (pinned, H7). Tool parity is kept (default `quiet = 0`);
the README leads its multi-file example with `quiet = 1` and says why.

### 2.5 mapRc, the partial-output rule, and the tool's stderr

head has no "answer" rc: `1` is always an error, so `mapRc` is `0→0`, else `1` + one
`kk.debug` line (`127` keeps the base wording). Two named deviations, both already
carried by tgrep and repeated in this README and the kcl README row: (a) a partial
failure (`a.txt missing`) delivers a's records with rc 1 and RESULT = the real count;
(b) the tool's own stderr (`head: cannot open 'missing'…`) passes through
unconditionally, and its quoting follows the locale. An overflowing count that
passes the regex but not the guard cannot reach the tool. A 19-digit value passes
both and is NOT an error for `-n` (it fits `uintmax`: `head -n 9999999999999999999`
is rc 0, measured at P0); the shape that really overflows is a NEGATIVE byte count,
`head -c -9999999999999999999` → rc 1 with the tool's own "Value too large" message
(pinned).

### 2.6 CRLF and `crlf`

head keeps the CR, so this is the unit where TUtil's `crlf = 1` finally does
something: pinned (`x\r\ny\r\n` → records `x`,`y` with `crlf = 1`, `x\r` without),
also in bytes mode (`bytes = 5` on that file → `x`, `y`).

### 2.7 `THead.take N PATH...`

Static one-liner, the `TGrep.search` shape: N validated by §2.2, ≥1 path required
(rc 2 — with none head would read the CALLER's stdin, tpipe §1.3), throw-away
instance, `run`, `delete`, rc = run's. Tool parity: with two or more paths the
headers are in the stream (pinned, H11). Streams; composes with both TPipe forms.

### 2.8 The `__th_` prefix must be refused as an out-name — a tutil edit

`tutil._badOut` hard-codes `kk._outName NAME __tu_ __tg_`; a THead `__th_*` local is
not refused today (measured: `h.argv __th_v` fills it, rc 0). No corruption occurs
yet because THead's `__th_*` namerefs live only inside `buildArgv`/`paths`, which
return before any out-name nameref is bound — but the family rule would be false for
two of four wrappers. Decision: **extend `tutil._badOut` to `__tu_ __tg_ __th_ __tt_`**
in P0 (a small cross-unit edit to `kcl/tutil/tutil.sh` + one tutil 001 case pinning
the four prefixes + the "writing a descendant" note: a new wrapper adds its prefix
there). Pinned here as H4b (`h.argv __th_v` → rc 2).

### 2.9 The tutil PLAN §7 row is amended

tutil PLAN §7 said "`-n` value through `kk.isInt`" and "`follow` … sinks refuse, `run`
only". Both are superseded: the count goes through the regex + guard of §2.2 (`kk.isInt`
would silently turn `+2` into `2` and `-0` into `0`); `follow` is ttail §2.1. P0 amends
that row in the same commit.

---

## 3. Pinned facts (tests)

| # | fact | test |
|---|---|---|
| H1 | argv per option singly and combined, byte-exact; `--` iff paths; extras AFTER the options and before `--`; `${h}_args` empty after `new h N PATH`; `addArg -n 5` after `lines = 3` yields both and the tool takes 5 (last-flag-wins, §1.3) | 004 |
| H2 | `lines`+`bytes`, `quiet`+`verbose`, `zeroTerminated` with 2 paths / with `verbose`, bad N (`x`, `1K`, `1 2`, `--5`, 20 digits), empty cmd → rc 2, RESULT '', nothing runs, `${inst}_argv` empty | 004 |
| H3 | `lines` `08`/`+3`/`-2`/`-0`/`+0`/`0` pass verbatim; the tool's reading (8 / 3 / all-but-2 / everything / nothing / nothing) pinned behaviourally; a 19-digit `-n` is rc 0 (uintmax), `-c -<19 digits>` is rc 1 with the tool's own message; 20 digits → rc 2 | 004/005 |
| H4 | every var in `_data` after `new` (incl. inherited `subshellOk`); `delete` frees `_paths`; **H4b** `h.argv __th_v` and `h.toArray __th_a` → rc 2 (§2.8) | 004 |
| H5 | `zeroTerminated` derives `nul` with the P3-F1 four-state sequence (one path) | 004 |
| H6 | `h.lines = 2; h.each cb` == bare `head -n 2` records; `count`/`toArray`/`first`/`toList` vs the bare tool; unterminated last record | 005 |
| H7 | two files without `-q`: 9 records for two terminated 3-line files under `-n 5`, 8 with the first unterminated; `first` = `==> A <==`; `quiet = 1` data only; `verbose = 1` on one file = 2 records | 005 |
| H8 | missing file among good ones: records kept, RESULT = count, rc 1, lastRc 1, one debug line; the tool's own stderr line matched by prefix (or under `LC_ALL=C`) | 005 |
| H9 | `crlf = 1` strips exactly one CR per record, also in bytes mode; `crlf = 0` keeps it | 005 |
| H10 | `-z` on a NUL-separated file → NUL records; the unterminated last NUL record delivered; a TEXT file under `-z` is one record | 005 |
| H11 | `THead.take 2 f` == `head -n 2 -- f` in all three positions (`\| od`, `< <( )`, direct); two paths → headers in the stream; no path rc 2; nested `take` from an `each` callback keeps the outer instance | 005 |
| H12 | `set -eu` children through both TPipe forms and `h.each`, every sink call guarded `\|\| rc=$?` (an unguarded rc 1 aborts the caller — the documented caller rule); debug switch: one line per rc 2 / tool-error path, silence on rc 0; the D6 subshell warning for `h.toArray` under `$( )`, silenced by `subshellOk = 1` | 006 |

## 4. Test model

Oracle = bare `head` on a fixture tree built with `kt_fixture_tmpdir_create` (files:
5 lines; 11 lines; a CRLF file; a NUL-separated file with an unterminated last
record; an unterminated last line — used ALONE and as the FIRST of two operands; a
name with a space; a name starting with `-`); GNU banner gate first in 005 (SKIP
otherwise); no own `EXIT` trap; children under `timeout 20`; any assertion on the
tool's own stderr matches a prefix or runs under `LC_ALL=C`. Files: `004_Argv.sh`
(never runs head), `005_Run.sh`, `006_Contract.sh`; `tests/tests.sh`.

## 5. Phases

- **P0 — the unit** (gate: 004–006 green on both bashes; tutil 001 + tgrep 004 still
  green; sweep): `thead.sh`, the three test files (red-first against a stubbed
  skeleton, counts in the ledger), README first cut, the `tutil._badOut` extension
  (§2.8) with its tutil 001 case, the tutil PLAN §7 amendment (§2.9). Same worker
  cycle as ttail P0.
- **P1 — closeout** (gate: sweep): `bench.sh` (`take` vs bare `head -n`,
  **interleaved, medians of ≥ 15 runs, gate 1.5×** — measured 1.07–1.30×; the
  wrapper's fixed cost is ~3.9 ms of `new`+`argv`+`delete` against a ~42 ms msys fork,
  so corpus size does not move the ratio and a non-interleaved loop reads up to 2.4×;
  `argv` fork-free), `tests/007_Bench.sh` (10× ceiling like tgrep), README final,
  `TEST_COVERAGE_NOTES.md`, kcl README §2 row (unit count 20 → 22 with ttail), ledger
  COMPLETE. Same worker cycle as ttail P1.

**P1 DONE 2026-09-16.** Delivered: `bench.sh` (sections a–e: argv cost with the
fork-free / runs-nothing proof; `new`+`argv`+`delete` on its own line; the GATED
`THead.take` vs the bare tool in the `-n 1` and `-n 5000` shapes, interleaved,
medians of NR = 21, means printed beside them; `count` vs the `wc -l` equivalent
published, not gated; zero forks over every member and `take` — rc 0 under
`bash -eu` on both bashes), `tests/007_Bench.sh` (9 cases, 10x ceiling,
2000-line corpus), README final (§8 Performance, §9 Tests),
`TEST_COVERAGE_NOTES.md` (182 rows), the kcl README §2 row, the ledger. Measured
on an idle box against GNU coreutils 8.32:

| | bash 5.2.37 | bash 5.3.9 |
|---|---|---|
| `take 1` vs bare `head -n 1` (medians of 21) | 39.40 / 34.14 ms = **1.15x** | 43.19 / 35.88 ms = **1.20x** |
| `take 5000` vs bare `head -n 5000` | 39.97 / 36.02 ms = **1.10x** | 41.12 / 33.23 ms = **1.23x** |
| `new` + `argv` + `delete` (the delta) | 3120.6 us/call | 3199.5 us/call |
| `buildArgv` / `argv NAME` | 653.4 / 1196.3 us | 692.2 / 1290.6 us |
| `h.count` vs `head -n 5000 \| wc -l` (published) | 725.67 / 51.05 ms = 14.21x | 731.64 / 48.93 ms = 14.95x |
| gates | **2/2 PASS** | **2/2 PASS** |

Two estimates in the P1 bullet above are refined by the measurement, and the
conclusion is unchanged: a whole tool run is **33–36 ms** (estimated ~42 ms) and
the wrapper's fixed delta is **3.1–3.3 ms** (estimated ~3.9 ms), so the ratio is
~(34 + 3.2)/34 and *falls* as the corpus grows — `-n 1` and `-n 5000` agree
within a few percent. Suite after P1: **182/182** on bash 5.2.37 and on 5.3.9,
threaded and under `--mode single`.

## 6. Traps (in addition to tutil PLAN §6, all binding)

- `kk.isInt` is NOT used for N (§2.2); the regex is held in a variable and tested with
  `[[ =~ ]]`, never an inline `$'...'`.
- Headers are records (§2.4) and their leading `\n` depends on the previous file's
  termination; a test that counts records on two files pins both shapes.
- `-z` + several paths/`verbose` is rc 2 (§2.3), never a derived `-0`.
- CR-bearing fixtures through `printf`, never an array literal (tutil PLAN §6).
- `take` in a callback of an outer `each`: unique instance name (§2.7).
- An overridden sink (ttail) ends `inherited X "$@" || rc=$?; local n="$RESULT";
  kk._return "$n"; return "$rc"` — a body that ends on `inherited` returns 0 where the
  base returned 1 (the compiled trailer replaces the rc; measured).
- Nothing shared between thead and ttail but the plan text.

## 7. Deliverables

`thead.sh`, `tests/tests.sh` + `004`–`007`, `bench.sh`, `README.md`,
`TEST_COVERAGE_NOTES.md`, `thead_ledger.json` COMPLETE, kcl README §2 row, the
`tutil._badOut` extension + tutil 001 case, the tutil PLAN §7 amendment.

## 8. Critic pass (2026-09-15)

An Opus critic reviewed the first draft with 12 probe scripts on both bashes; the
findings and where each landed (the ttail-specific ones are in the ttail plan):

| # | sev | finding | landed in |
|---|---|---|---|
| 1 | BLOCKER | a `func` override ending on `inherited` returns 0 where the base returned 1 | §6 (spelling), ttail §2.1 |
| 2 | BLOCKER | "rc 2 at buildArgv" for `follow` is unimplementable (buildArgv does not know the caller; `_prep`'s `__tu_m` is unset on the `argv`/`run` paths) | ttail §2.1 (overridden sinks) |
| 3 | BLOCKER | `-z` + several files → one record (headers stay `\n`-terminated; `-z` re-delimits the input) | §1.1, §2.3 (rc 2 with ≥ 2 paths or verbose) |
| 4 | MAJOR | `first`/`each`/`toList` also hang under `follow` without a stopping consumer; no kcl list stops | ttail §2.1 |
| 5 | MAJOR | the "blank line between files" is a `\n` prefix on later headers; count depends on termination (the critic's "7" for the unterminated pair was off by one: it is 8, corrected at P0) | §1.1, §2.4, H7, §4 fixture |
| 6 | MAJOR | `-0`/`+0` and the sign mean opposite things in head and tail | §1.1, §2.2 table, H3 |
| 7 | MAJOR | a 1.3× bench gate flakes; corpus size is irrelevant (~42 ms fork vs ~3.9 ms wrapper) | §5 P1 (1.5×, interleaved medians ≥ 15) |
| 8 | MAJOR | `tutil._badOut` hard-codes `__tu_ __tg_`; `__th_`/`__tt_` not refused | §2.8 (tutil edit), H4b |
| 9 | MINOR | an overflowing count reaches the tool as an ordinary rc 1 (at P0: only the `-c -N` shape overflows; a 19-digit `-n` is rc 0) | §2.2 (19-digit guard), §2.5, H3 |
| 10 | MINOR | the tool's stderr is unconditional and locale-quoted | §1.1, §2.5 (b), §4 |
| 11 | MINOR | extras come last; `addArg -n/-c` replaces `lines`/`bytes` silently | §1.3, H1 |
| 12 | MINOR | tutil PLAN §7 row contradicts both plans (`kk.isInt`, "sinks refuse") | §2.9 |
| 13 | MINOR | `take` with several paths emits headers | §2.7, H11 |
| 14 | MINOR | `tail -f` children leak; msys poll ~1 s; follow latency differs per bash | ttail §4 |
| 15 | MINOR | no shared file between the units | header, §6 |
| 16 | MINOR | `--pid` is the only self-terminating follow | ttail §2.1 |
| 17 | NIT | `kcl/tgrep/PLAN.md` does not exist | header (tgrep.sh header + README + 004 §G) |
| 18 | NIT | an unguarded sink call with rc 1 aborts a `set -e` caller | H12 |
| 19 | NIT | an unterminated last NUL record stays unterminated | §2.3, H10 |

Verified correct by the critic (not to be re-probed): coreutils 8.32 first on PATH
under both bashes; the count forms of §1.1; rc 1 for every error incl. partial
output; headers-as-records shapes; `quiet`+`verbose` refusal justified (last flag
wins silently); CR kept and `crlf = 1` strips one per record incl. bytes mode; the
tpipe stop path ends `tail -f` in ~45 ms with lastRc 143 on both bashes (no
`---disable-inotify` needed); the tgrep mechanics (constructor, `_paths`, `_badOut`
on `_paths`, ordered tails, `_nulDerived` four states) behave identically in a
prototype; `take` byte-identical to the bare tool in three positions and nested-safe;
D6 warning + `subshellOk`; `argv` 1.4 ms and fork-free; `--`/`-`/stdin operand
handling; `kt_fixture_tmpdir_create` exists.
