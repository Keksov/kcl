# TFind — GNU `find` wrapper over TUtil (kcl/tfind)

**Status: PLANNED, critic-hardened (2026-09-16). No code yet.** Owner: "приступай к
tfind" (2026-09-16). A critic pass (§8) found 2 blockers and 5 majors in the first
draft; every one is folded in below. Third wrapper after tgrep, thead, ttail;
everything those units settled applies (the tgrep constructor rule, `kk.call_silent`,
`_nulDerived` with the P3-F1 guard, the rc-preserving override spelling, the
one-liner on a unique throw-away instance, the named deviations, D6/`subshellOk`).
Read first: `kcl/thead/PLAN.md` (§2, §6, §8), `kcl/thead/thead.sh` and
`kcl/ttail/ttail.sh` (the newest wrapper bodies), `kcl/tutil/README.md` "Writing a
descendant", `kcl/tgrep/tests/004_Argv.sh` §G.

**Source of truth:** GNU findutils 4.10.0 `find` as shipped by MSYS2. Both target
bashes are MSYS builds (`uname -o` = Msys for 5.2.37 and for the 5.3.9 at
`C:/bin/msys64`), each resolving its own root's `/usr/bin/find`, both 4.10.0; every
probe below gave byte-identical results on the two. D4: GNU dialect, PATH-resolved
binary, banner gate in the behavioural tests.
**Base:** `TFind : TUtil`. **Ledger:** `kcl/tfind/tfind_ledger.json`. **Prefix:**
`__tfd_` (`__tf_` is tfile's). No `static var`. Sources `../tutil/tutil.sh` only.

---

## 1. Scoping

### 1.1 The tool, measured (findutils 4.10.0, both bashes)

| probe | result |
|---|---|
| grammar | `find [-H\|-L\|-P] [START...] [EXPRESSION]` — start points come FIRST and the expression after them: the reverse of grep/head. `-L`/`-H`/`-P` are accepted only BEFORE the start points (`find tree -L` → "unknown predicate `-L'", rc 1) |
| `--` | ends the **option** list only (`-H/-L/-P`, `--version`); it does NOT protect a start point: `find -- -weird` is still "unknown predicate", rc 1. `--` cannot rescue a start point, so the wrapper never emits it |
| a start point beginning with `-`, `!` or `(` | read as the expression → error rc 1; `)` and `,` are fine; `./-weird` works; `-` is not stdin (`No such file`, rc 1); `''` is `find: '': No such file or directory`, rc 1 |
| no start point | searches `.` (records `./…`); an expression may follow directly (`find -maxdepth 1 -name x` works); `find` alone works; an existing FILE is a valid start point |
| rc | `0` ok; `1` for a missing start point among good ones (the good ones are searched and printed — partial output), `-newer MISSING` (**fatal**: no traversal, no records), `-maxdepth x`, a depth above `INT_MAX` (`2147483648: Numerical result out of range`), `-type f,f` (duplicate), `-exec … {} +` whose command fails or is missing. **`-exec CMD {} \;` whose command fails or is missing leaves rc 0** (stderr only) |
| `-maxdepth 08` | decimal 8; `-maxdepth +1` is **rc 1** ("Expected a positive decimal integer … got '+1'") — the emitted value must be `kk.isInt`'s normalised `$__KK_INT`, never the property verbatim |
| global-option order | 4.10 no longer warns about `-name X -maxdepth 1`; the wrapper still emits the global options first |
| `-type` | `f,d` comma lists accepted; `f,f` refused (duplicate, rc 1); `''`, `f,` refused; `D` refused on this platform |
| `-name` / `-iname` | `-name` is case-SENSITIVE on NTFS under msys (`b.TXT` vs `B.TXT` differ), `-iname` insensitive; a pattern containing `/` matches nothing silently; `-name ''` matches nothing, rc 0 |
| actions | `-print` is implied when the expression has no action; an explicit action (`-print0`, `-exec …`) suppresses the implied one; two actions both run and their output interleaves on one stream; actions are ANDed — `-exec false {} \; -print0` prints nothing, rc 0; `-quit -print0` prints nothing, `-print0 -quit` prints one |
| `-print` / `-print0` | a name containing a newline is split by `-print` and intact under `-print0` |
| Windows paths | `C:\…\tree` and `C:/…/tree` accepted under both bashes; the start point's spelling survives as a PREFIX and every separator find appends is `/` (`C:\…\tree/a.txt`); UNC `\\host\share` is refused (rc 1); a trailing slash is normalised away |
| `-L` | descends a real directory symlink (`-P`, the default, does not); under `-L` `-type l` matches only broken links |
| permissions | `chmod 000` and `icacls /deny` do not stop find on this box (rc 0, full output) — no permission test is planned |
| stderr | the tool's own diagnostics are unconditional and locale-quoted |

### 1.2 Surface

```bash
class TFind : TUtil
    public
        var name            # -name PATTERN   ('' = off; one argv element, never expanded by the wrapper)
        var iname           # -iname PATTERN  ('' = off)
        var type            # -type T, T = [bcdflps](,[bcdflps])*  ('' = off; else rc 2; a duplicate like f,f passes the regex and is the tool's rc 1)
        var maxDepth        # -maxdepth N  (kk.isInt, >= 0, emitted as $__KK_INT; '' = off)
        var minDepth        # -mindepth N  (same)
        var newer           # -newer FILE ('' = off; a missing FILE is the tool's FATAL rc 1)
        var followSymlinks  # 1 → -L, emitted BEFORE the start points
        var print0          # 1 → -print0 as THE action → derives the sinks' -0 (P3-F1 guard); incompatible with an action in the extras (§2.3)
        var _nulDerived
        constructor Create  # [START...] — every argument is a start point; assigns EVERY var; parent.constructor find
        destructor  Destroy # frees ${inst}_paths, then inherited
        proc paths          # START... replaces the start-point list; NO arguments = find's own `.`
        override func buildArgv   # find [-L] [START...] [-maxdepth N] [-mindepth N] [-name P] [-iname P] [-type T] [-newer F] [extras] [-print0]
        override func mapRc       # 0→0; else 1 + one debug line
        static proc byName        # TFind.byName PATTERN START... → `find START... -name PATTERN` stream; ≥1 start point required
end
```

`type` is a plain property name (kklass generates `f.type`; inside a member it is the
nameref `$type`; the `type` builtin is a different namespace — verified). Reserved
TUtil/kklass names as in thead §1.2.

argv shape, pinned: `find` `[-L]` `[START...]` `[-maxdepth N]` `[-mindepth N]`
`[-name P]` `[-iname P]` `[-type T]` `[-newer F]` `[EXTRA ARGS from addArg]`
`[-print0]`. No `--` (§1.1). Extras land in the expression, after the typed tests
and before the action: `addArg -size +1M`, `addArg -mtime -1`, `addArg '!' -name x`,
`addArg '(' -name a -o -name b ')'` all work as argv elements. `-L` cannot be given
through `addArg` (wrong position) — that is why `followSymlinks` is typed.

### 1.3 Not in scope

1. `-H`/`-P` (the default is `-P`; wontfix). 2. `-regex`, `-path`, `-size`, `-mtime`,
   `-empty`, boolean operators and groups: `addArg`, in expression order.
3. **Actions through `addArg`** (`-exec`, `-execdir`, `-ok`, `-okdir`, `-delete`,
   `-ls`, `-fls`, `-printf`, `-fprint*`, `-print`, `-print0`, `-quit`) are allowed only
   with `print0 = 0`: the extra's output IS the record stream (the implied `-print` is
   suppressed — tool parity); with `print0 = 1` they are refused (§2.3). A caller who
   needs `-print0` in a hand-built position (`addArg -print0 -quit`) sets `nul = 1`
   manually and keeps `print0 = 0`.
4. Order-incompatible predicates: `-quit` and `-prune` must precede the action, and
   `-delete` replaces it — with the fixed action position they are only usable as in
   item 3 (`print0 = 0`, hand-built). Documented, not modelled.
5. BSD find (D4). 6. UNC start points (the tool refuses them).

---

## 2. Design decisions

### 2.1 Start points are positional, not `--`-separated

`buildArgv` emits `[-L]`, then the start points verbatim, then the expression. `paths`
with no arguments = an empty list = find's own `.` (records `./…`) — tool parity,
documented. A start point that is **empty** or matches `^[-!(]` is **rc 2** at
buildArgv, nothing runs (the message names `./-weird` and "call `paths` with no
arguments for `.`"). A start point may be a Windows path; the records carry its
spelling as a prefix with `/` separators after it (pinned that way, not as
whole-record equality).

### 2.2 The typed expression, in a fixed order

Global options first (`-maxdepth`, `-mindepth`), then the tests in the order of §1.2,
then the extras, then the action. `name`/`iname`/`newer` are one argv element each
and never glob-expanded by the wrapper (pinned with `*`, `?`, `[` and a space in the
pattern). The CALLER's side is the real-world trap: `f.name = *.txt` unquoted expands
at the call site and the property setter keeps only the first word, silently
(measured) — README rule + one 004 case: always `f.name = '*.txt'`. `type` validated
by `^[bcdflps](,[bcdflps])*$` (a duplicate list passes and is the tool's rc 1 —
parity, documented). `maxDepth`/`minDepth` through `kk.isInt` + `>= 0`, **emitted as
`$__KK_INT`** (`08` → 8, `+1` → 1 — verbatim `+1` would be the tool's rc 1); a value
above `INT_MAX` passes the guard and is the tool's rc 1 (parity). `minDepth >
maxDepth` is not refused (find answers nothing, rc 0).

### 2.3 `print0` derives `-0` and excludes every other action

`print0 == 1` → `-print0` is the action and `nul=1` / `_nulDerived=1` unless `nul` was
already 1 (the P3-F1 guard); undone when `print0` goes back to 0. No header exception
(find has no headers). **With `print0 == 1`, an extra from `addArg` that is an
action** — any of `-print -print0 -printf -fprint -fprint0 -fprintf -ls -fls -exec
-execdir -ok -okdir -delete -quit` — **is rc 2 at buildArgv**: measured, two actions
interleave into one corrupted NUL record (`X:./a.txt\n./a.txt\0`), and an `-exec`
that exits non-zero short-circuits the AND chain so `-print0` never fires — rc 0,
zero records, no diagnostic. The README leads every sink example with `print0 = 1`:
a file name containing a newline is two records under `-print` and one under
`-print0` (pinned).

### 2.4 mapRc, partial output, the tool's stderr, `-exec \;`

`0→0`, else `1` + one `kk.debug` line (`127` keeps the base wording). Three named
deviations, in the README and the kcl README row: (a) a missing start point among
good ones still prints the good ones — records delivered, RESULT = the real count,
rc 1; (b) the tool's own stderr passes through unconditionally (tests match a
prefix); (c) `-exec CMD {} \;` whose command fails or is missing leaves find at rc 0
(stderr only) — the `+` form propagates the failure as rc 1; a caller who needs the
child's status in `lastRc` uses `{} +`. `-newer MISSING` is a **fatal** rc 1 with no
records (not partial output) — pinned separately from (a).

### 2.5 `TFind.byName PATTERN START...`

`find START... -name PATTERN` on a throw-away instance `__tfd_b_${BASHPID}_${__TFD_SEQ}`;
≥ 1 start point required (rc 2 — with none find would search the caller's cwd, which
no one means by accident in a one-liner); `-print` implied; streams; composes with
both TPipe forms; a refused start point propagates rc 2 through `run`.

### 2.6 `tutil._badOut` becomes a registry — reserved and fail-closed

Three wrappers have edited `tutil._badOut`'s hard-coded prefix list; this unit turns
it into a registry: `tutil.sh` declares `TUTIL_OUT_PREFIXES=(__tu_ __tg_ __th_ __tt_)`
at load and `_badOut` passes `"${TUTIL_OUT_PREFIXES[@]}"`; `tfind.sh` appends `__tfd_`
at load (only if absent — idempotent under re-source). Two guards the critic showed
are necessary: (1) **the registry's own name is refused as an out-name** (an explicit
`case` in `tutil._badOut` for `TUTIL_OUT_PREFIXES`) — otherwise one `f.argv
TUTIL_OUT_PREFIXES` replaces the registry with the argv and every `__tu_`/`__tg_`/…
name becomes fillable process-wide (measured); (2) **fail closed**: an empty or
non-array registry (bash ≥ 4.4 does not even fault `"${arr[@]}"` on an unset array
under `set -u`) makes `_badOut` refuse EVERY name (rc 2) rather than none. Existing
tutil/tgrep/thead/ttail tests are unchanged; tutil 001 gains the cases: `__tfd_x`
refused after sourcing tfind, `TUTIL_OUT_PREFIXES` refused as a NAME, an emptied
registry refuses `plain` and the four family prefixes, the registry restored has five
entries. tutil README "writing a descendant": append your prefix; tutil PLAN §7 tfind
row amended.

---

## 3. Pinned facts (tests)

| # | fact | test |
|---|---|---|
| F1 | argv per option singly and combined, byte-exact, in the pinned order; `-L` before the start points; no `--`; extras between the tests and the action; `${f}_args` empty after `new f START` | 004 |
| F2 | rc 2: a start point `''` or matching `^[-!(]`, `type` outside the regex, `maxDepth`/`minDepth` non-int or negative, `print0 = 1` + an action extra (each word of the §2.3 set, incl. `-print0` and `-quit`), empty cmd — RESULT '', nothing runs, `${inst}_argv` empty | 004 |
| F3 | `maxDepth = 08` → `-maxdepth 8`, `= +1` → `-maxdepth 1` (`$__KK_INT`); `type = f,f` passes the regex and is the tool's rc 1 | 004/005 |
| F4 | every var in `_data` after `new`; `delete` frees `_paths`; `f.argv __tfd_v` → rc 2; `f.argv TUTIL_OUT_PREFIXES` → rc 2 and the registry intact; `__tu_x`… still refused | 004 |
| F5 | `print0` derives `nul` with the four-state sequence | 004 |
| F5b | the caller-side glob trap: `f.name = *.txt` unquoted in a directory with two `.txt` files keeps one word (documented behaviour); `f.name = '*.txt'` keeps the pattern | 004 |
| F6 | `name`/`iname`/`type`/`maxDepth`/`minDepth`/`newer`/`followSymlinks` each vs the bare tool on the fixture tree (sorted with `sort -z`, §4); `type = f,d`; `-name` case-sensitive vs `-iname` on NTFS; `-L` descends a real directory symlink and the default does not (`kt_make_symlink` from `../../tdirectory/tests/symlink_helper.sh`, SKIP via `kt_symlinks_supported`); `followSymlinks = 1` + `type = l` matches only broken links (documented) | 005 |
| F7 | a name with a newline: two records under `-print`, one under `print0 = 1`; a name with a space intact; `./-weird` as a start point works while `-weird` is rc 2 | 005 |
| F8a | missing start point among good ones: records kept, RESULT = count, rc 1, lastRc 1, one debug line, `first` still rc 0 | 005 |
| F8b | `newer` = missing file: fatal — zero records, rc 1, lastRc 1 | 005 |
| F9 | empty start-point list → records `./…` from a `cd` into the fixture **in the test file's own shell** (then `cd` back), never in a subshell (D6) | 005 |
| F10a | `print0 = 0` + `addArg -exec printf 'X:%s\n' {} \;` — the exec output IS the record stream (implied `-print` suppressed); `-exec false {} \;` → rc 0 and zero records (deviation (c)); `-exec … {} +` with a failing command → rc 1 | 005 |
| F10b | `print0 = 1` + `addArg -size +0` (non-empty fixture files) keeps NUL framing; `print0 = 1` + `addArg -exec …` is rc 2 (F2) | 005 |
| F11 | `TFind.byName '*.txt' DIR` == `find DIR -name '*.txt'` in three positions; no start point rc 2; nested `byName` from an `each` callback keeps the outer instance | 005 |
| F12 | `set -eu` children through both TPipe forms and `f.each`, every sink call guarded; debug switch one line per rc 2 / tool-error path, silence on rc 0; D6 warning + `subshellOk`; a Windows-spelled start point yields records whose PREFIX is that spelling and whose separators after it are `/` | 006 |

## 4. Test model

Oracle = bare `find` on a fixture tree from `kt_fixture_tmpdir_create` (absolute
`_KT_TMPDIR`): depth 3, files `a.txt`, `sub/b.TXT`, `sub/deep/c.txt` — every file
holds `x\n` (non-empty, for `-size +0`) — a name with a space, a name with a newline,
a directory named `-weird` with a file inside, a directory symlink via
`kt_make_symlink`. Banner gate first in 005 (`find (GNU findutils) `); no own `EXIT`
trap; children under `timeout 20`; the tool's stderr matched by prefix. **The
comparison primitive**: traversal order is not pinned, and a newline-bearing name is
destroyed by a line-based sort, so both sides go through `mapfile -d '' -t X < <(printf
'%s\0' "${arr[@]}" | sort -z)` and the oracle is `mapfile -d '' -t O < <(find …
-print0)` (or the `-print` stream for the split-name case). Files: `004_Argv.sh`,
`005_Run.sh`, `006_Contract.sh`, `tests.sh`.

## 5. Phases

- **P0 — the unit** (gate: 004–006 green on both bashes; tutil/tgrep/thead/ttail
  still green on 5.2.37; sweep): `tfind.sh`, tests, README first cut, the
  `TUTIL_OUT_PREFIXES` registry in tutil with its guards (+ tutil 001 cases + README
  note + PLAN §7 tfind row).
- **P1 — closeout** (gate: sweep): `bench.sh` (`byName` vs bare `find -name`,
  interleaved medians ≥ 15, gate 1.5× — measured 1.13×/1.16× on a 400-file tree and
  1.15×/1.21× on a 1-file tree: the ~32 ms fork dominates and the wrapper's fixed cost
  is ~4.7 ms (nine properties); the worst single-sample pairing reads 1.64×, so the
  interleaved-median protocol is non-negotiable and the bench file says why; clock =
  `TStopwatch.getTimeStamp`, never `date +%s%N` (~20 ms per call on msys)),
  `tests/007_Bench.sh` (10× ceiling), README final, `TEST_COVERAGE_NOTES.md`, kcl
  README §2 row (22 → 23), ledger COMPLETE.

## 6. Traps (in addition to tutil PLAN §6 and thead §6)

- Start points are positional: never emit `--` (it does nothing for them); refuse `''`
  and `^[-!(]` (§2.1). The character class is `[-!\(]*` in `[[ == ]]` — `[!-(]*` is a
  NEGATED class and silently stops refusing `-x`; with `=~` the `-` stays first.
- `-L` before the start points only; `addArg -L` is silently wrong → typed
  `followSymlinks`.
- Depths are emitted from `$__KK_INT`, never the property (`+1` verbatim is rc 1).
- Patterns are argv elements: no quoting layer, no `eval`, never `$pattern` unquoted;
  the caller quotes the pattern at the call site (§2.2).
- `print0 = 1` excludes every action in the extras (§2.3); `-quit`/`-prune`/`-delete`
  are order-incompatible with the fixed action position (§1.3).
- The traversal order is not pinned; a line-based sort breaks newline names: `sort -z`
  only (§4).
- F9's `cd` happens in the test file's shell, never in `( )`.
- `followSymlinks = 1` + `type = l` is a near no-op (only broken links) — documented.

## 7. Deliverables

`tfind.sh`, `tests/tests.sh` + `004`–`007`, `bench.sh`, `README.md`,
`TEST_COVERAGE_NOTES.md`, `tfind_ledger.json` COMPLETE, kcl README §2 row, the
`TUTIL_OUT_PREFIXES` registry with its two guards + tutil 001 cases + README note +
tutil PLAN §7 row.

## 8. Critic pass (2026-09-16)

An Opus critic reviewed the first draft with 18 probe scripts on both bashes:

| # | sev | finding | landed in |
|---|---|---|---|
| 1 | BLOCKER | the registry array is itself a fillable out-name (one `f.argv TUTIL_OUT_PREFIXES` disarms the family guard process-wide) and fails OPEN when empty/unset | §2.6 (reserved name + fail closed), F4 |
| 2 | BLOCKER | `print0 = 1` + an action extra: two actions interleave into one corrupted NUL record; `-exec false` short-circuits `-print0` (rc 0, zero records) | §2.3 (rc 2), §1.3, F2, F10 |
| 3 | MAJOR | `--` ends the OPTION list only; `find -- -weird` still fails — the first draft's row suggested it could rescue a start point | §1.1, §2.1 |
| 4 | MAJOR | `-exec CMD {} \;` failures leave rc 0; the `+` form propagates | §1.1, §2.4 (c), F10a |
| 5 | MAJOR | F9's `cd` in a subshell fills the array where the assertion cannot see it (and trips D6) | §4, F9 |
| 6 | MAJOR | a line-based sort turns a newline name into extra elements | §4 (`sort -z`), F6 |
| 7 | MAJOR | an empty start point `''` reaches the tool (rc 1) | §2.1, F2 |
| 8 | MINOR | the `type` regex admits duplicates find refuses | §1.2, §2.2, F3 |
| 9 | MINOR | `+1` verbatim is the tool's rc 1; `> INT_MAX` is rc 1 | §1.1, §2.2, F3 |
| 10 | MINOR | `-newer MISSING` is fatal, not partial | §2.4, F8b |
| 11 | MINOR | a Windows start point survives only as a prefix | §1.1, §2.1, F12 |
| 12 | MINOR | `-L` + `type = l` matches only broken links | §1.1, F6 |
| 13 | MINOR | `-quit`/`-prune`/`-delete` are order-incompatible with the fixed action | §1.3 |
| 14 | MINOR | `-name` is case-sensitive on NTFS under msys; `/` in a pattern and `''` match nothing silently | §1.1, F6 |
| 15 | MINOR | caller-side glob expansion keeps one word silently | §2.2, F5b |
| 16 | MINOR | `-size +0` needs non-empty fixture files | §4, F10b |
| 17 | MINOR | bench: worst single pairing 1.64×, `date +%s%N` costs ~20 ms | §5 |
| 18 | NIT | `[!-(]*` is a negated class | §6 |
| 19 | NIT | `kt_make_symlink` lives in tdirectory's helper, gate = `kt_symlinks_supported` | F6 |
| 20 | NIT | no permission-denied test is possible on this box | §1.1 |

Verified correct by the critic (not to be re-probed): findutils 4.10.0 under both
bashes; no start point + an expression works; a file as a start point; `-` is not
stdin; `)`/`,` are fine as start points; partial output on a missing start point with
RESULT = the real count through the sinks; `-maxdepth 08`; `-type f,d`; `-name`
case-sensitive vs `-iname`; `-print` splits / `-print0` keeps a newline name;
`print0`-derived `-0` + `toArray` byte-identical to `mapfile -d '' < <(find … -print0)`;
Windows start points accepted under both bashes; `var type` safe; the registry
append idempotent; `byName` ≥ 1 start point, rc 2 propagation, nested-safe,
composable; `kk.isInt` normalisation; sinks `set -eu`-safe when guarded; D6 warning;
`sort -z` available; the ktests fixture helpers exist and `_KT_TMPDIR` is absolute;
`cd` in a test file is an established pattern (tpath 009); the bench premise.
