# tgrep — test coverage notes

**Status: updated at tutil P4 (D6 final, `subshellOk`, 2026-09-15); previously
FINALIZED at P3 (2026-09-11).** Suite `004`–`007` = **185 cases**,
green on bash 5.2.37 (primary) and on bash 5.3.9 (secondary), in the default
threaded mode and under `--mode single`, against **GNU grep 3.0**. The per-file
row counts below sum to 185 — 74 + 53 + 49 + 9 — and **every case in the suite
has a row**.

**Protocol.** `TGrep` has no FPC upstream: it is the first wrapper on
[`TUtil`](../tutil/README.md), which is itself a kcl addition (see
[../tutil/docs/TUtil.md](../tutil/docs/TUtil.md)). The oracle is therefore **the
bare GNU tool on the same fixture**, run with the same argv, never a second call
into the code under test. Decision **D4** pins the *dialect* (GNU grep 3.0, the
build MSYS2 ships), not a binary, so every behavioural file opens with the **GNU
banner gate**: if `grep --version` does not begin with `grep (GNU grep) ` — this
box also carries a non-GNU `grep` from Embarcadero that can win the PATH race —
every behavioural case is a loud SKIP and the case **count is unchanged**.

The suite splits in two on purpose:

* **`004_Argv.sh` never executes grep.** Every typed option is pinned by
  comparing the built array, which is what `argv NAME` exists for; it is the fast
  half and it is where a wrapper's surface actually lives.
* **`005`/`006`/`007` run the tool** on a fixture tree with names containing a
  space, a newline and a leading `-`, UTF-8, CRLF, a NUL byte, a subdirectory and
  **real** NTFS symlinks (a plain `ln -s` makes a directory *copy* on this box —
  critic finding C7 — so they go through the tdirectory helper `kt_make_symlink`).

The Basis column cites one of:

* **G1–G12** — a pinned fact of `../tutil/PLAN.md` §3.
* **C1–C23** — a finding of the 2026-09-10 critic pass (`../tutil/PLAN.md` §8).
  The measurement behind each blocker is
  [../tutil/docs/TUtil.md §3](../tutil/docs/TUtil.md#3-the-measurements).
* **P2-Fn / P3-Fn** — a finding made by the implementing worker in that phase
  (`../tutil/tutil_ledger.json` `execution_log`).
* **D2 / D4 / D6** — an owner or supervisor decision.
* **§n** — a section of `../tutil/PLAN.md` (or of this README) where the rule is
  stated.

**Classes.**

| Class | Meaning |
|---|---|
| `contract` | the kcl contract (`../README.md` §1): rc mapping, `RESULT`, silence, validation order, `set -eu` cleanliness, lifecycle, zero forks |
| `argv` | the typed option set → the pinned command line, asserted **without running grep** |
| `tool-behaviour` | what GNU grep 3.0 actually does, measured against the bare tool as oracle |
| `representation` | paths and records are **data**: a space, a newline, a leading `-`, UTF-8, a CR, a NUL delimiter, a binary file |
| `boundary` | an edge the happy path never reaches: no match, no path, a missing operand among good ones, nesting, a symlink |
| `perf` | a `PLAN.md` §5 P3.1 gate, asserted with a loose ceiling |

**Deliberate gaps** (each is a `wontfix` of `../tutil/PLAN.md` §1.4, restated in
README §1):

* **`-P` (PCRE)** — optional in a GNU build and absent from the house ERE line
  ([tregex](../tregex/README.md)); nothing to assert;
* **`--color`** — never emitted; the output is data;
* **context (`-A`/`-B`/`-C`)** — breaks the one-record-one-match model of the
  sinks; `addArg` + `run` is the documented way to it, and *that* is pinned
  (005 §J);
* **`-a` / `-I` as typed properties** — a later wave; the escape hatches
  (`addArg -a`, `addArg --binary-files=text`) are pinned instead (005 §K);
* **grep's own stderr** — the tool's `grep: …` lines pass through untouched by
  design, so 006 counts *our* lines and the tool's separately and asserts only
  that ours are silent;
* **BSD/macOS dialects** (D4).

**`P3-F1`, found and fixed at P3.** The §4 `-0` derivation used to claim
ownership of `nul` whenever the derivation *condition* held — even when `nul` was
already `1` because the caller had set it — so a later build that stopped
deriving cleared the caller's own value. It was found while writing the docs,
fixed in the same phase with a one-line guard, and pinned by the last case of
004 §G below (red-first: 1 FAIL of 184 against the unguarded code). The full
before/after measurement is in
[../tutil/docs/TUtil.md §3.8](../tutil/docs/TUtil.md#38-27--the--0-derivation-and-the-shape-it-used-to-get-wrong).

---

## 004_Argv.sh — typed options to argv, nothing executed (P2) — 74 cases

**grep is never started in this file.** Every case either compares the array
`g.argv GOT` handed over, or asserts a refusal.

### A. lifecycle — `Create` assigns every var, the arrays are right (7)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.vars-present | Create | all 23 declared vars **plus TUtil's five** (`cmd`, `crlf`, `nul`, `_lastRc`, `subshellOk`) are present in `${inst}_data` right after `new` | contract | **C3**, §2.1, **D6 final Q9** |
| 004.vars-defaults | Create | the documented defaults: booleans `0` (**`subshellOk` among them**), strings `''`, `cmd` `grep`, `_lastRc` `-1` | contract | §2.1 |
| 004.args-empty | Create | `${g}_args` is EMPTY after `TGrep.new g PAT PATH` | contract | **C2** — the `inherited` trap doubled every path ([docs §3.2](../tutil/docs/TUtil.md#32-c2--inherited-in-a-constructor-forwards-)) |
| 004.paths-verbatim | Create | `${g}_paths` holds the constructor's paths verbatim, once each | representation | §2.1 |
| 004.reuse-clean | Create | a REUSED instance name starts clean — every var re-assigned | boundary | **C3** |
| 004.delete-chains | Destroy | `delete` removes `_paths`, `_args` AND `_argv` (the descendant destructor chains with `inherited`) | contract | §1.9, §2.1 |
| 004.argv-nothing | argv | `argv` RUNS NOTHING — not even a `cmd` that exists | contract | §1.2 |

### B. G1 — every flag, singly (23)

Each case resets the instance, sets exactly one property, and compares the whole
array against `grep FLAG -e pat -- f`. Class `argv`, basis **G1** throughout.

| ID | Case |
|---|---|
| 004.g1-none | no option at all — `grep -e PATTERN -- PATH` |
| 004.g1-i | `ignoreCase = 1` → `-i` |
| 004.g1-v | `invert = 1` → `-v` |
| 004.g1-w | `wordRegexp = 1` → `-w` |
| 004.g1-x | `lineRegexp = 1` → `-x` |
| 004.g1-F | `fixed = 1` → `-F` |
| 004.g1-E | `extended = 1` → `-E` |
| 004.g1-r | `recursive = 1` → `-r` — **never `-R`**: a directory symlink is not followed (§2.5, G12) |
| 004.g1-n | `lineNumber = 1` → `-n` |
| 004.g1-l | `filesOnly = 1` → `-l` |
| 004.g1-L | `filesWithoutMatch = 1` → `-L` |
| 004.g1-c | `countOnly = 1` → `-c` |
| 004.g1-o | `onlyMatching = 1` → `-o` |
| 004.g1-h | `noFilename = 1` → `-h` |
| 004.g1-H | `withFilename = 1` → `-H` |
| 004.g1-U | `binary = 1` → `-U` — the only way to see a CR through grep (§2.6, **C8**) |
| 004.g1-z | `nullData = 1` → `-z` (NUL-terminated INPUT records) |
| 004.g1-Z | `nullOut = 1` → `-Z` |
| 004.g1-m | `maxCount = 3` → `-m 3` as TWO words |
| 004.g1-include | `include = '*.txt'` → `--include=*.txt` |
| 004.g1-exclude | `exclude = '*.o'` → `--exclude=*.o` |
| 004.g1-excludedir | `excludeDir = '.git'` → `--exclude-dir=.git` |
| 004.g1-include-space | `include = 'my docs/*.txt'` is ONE word, unexpanded (`representation`) |

### C. G1 — combinations, the pinned order, the boolean rule (6)

| ID | Case | Class | Basis |
|---|---|---|---|
| 004.g1-in | `-i` and `-n` together, in the pinned order | argv | **G1** |
| 004.g1-order | the ORDER is `buildArgv`'s, not the order the caller assigned in | argv | **G1**, §1.3 |
| 004.g1-ErlZ | `-E -r -l -Z` — the classic "list the files" shape | argv | **G1** |
| 004.g1-all | EVERYTHING on at once — the full pinned order, two paths | argv | **G1**, §1.3 |
| 004.g1-other-half | the other side of each pair — `-E`, `-L`, `-H` | argv | **G1** |
| 004.g1-boolean | a boolean is ON only for the exact string `1` (`2`, `yes`, `true`, `01`, `' 1'` are off) | contract | §6 — never `(( x ))`: a string is 0 in silence, or an arithmetic injection |

### D. G1 — `-e` always, `--` only with paths, extras in place (10)

| ID | Case | Class | Basis |
|---|---|---|---|
| 004.g1-nopath | `TGrep.new g PAT` with no path is `grep -e PAT` — **no `--`** | argv | **G1**, §1.3 — the stdin form |
| 004.g1-path-space | one path → `-- 'a b'`: a space is safe by construction | representation | **G1** |
| 004.g1-three-paths | three paths, all after the one `--` | argv | **G1** |
| 004.g1-extra-slot | an `addArg` extra lands AFTER `-e PATTERN` and BEFORE `--` | argv | **G1**, §1.3 |
| 004.g1-extras-order | several extras keep their order, still between `-e PAT` and `--` | argv | **G1** |
| 004.g1-clearargs | `clearArgs` empties the extras again | argv | **G1** |
| 004.g1-paths-replace | `g.paths new1 'new 2'` REPLACED both old paths | argv | §1.3 |
| 004.g1-paths-empty | `g.paths` with no argument is the stdin form | boundary | §1.3 |
| 004.g1-no-accumulate | rebuilding does not ACCUMULATE — two `argv` calls agree | boundary | §2.2 |
| 004.g1-copy | `argv` hands over a COPY — writing it does not touch `${inst}_argv` | contract | §1.7 |

### E. G2 — the rc 2 list: nothing runs, RESULT `''`, one line (7)

Each refusal asserts rc 2, `RESULT=''`, the caller's array **untouched**, and
exactly ONE `kk.debug` line naming the reason. Class `contract`, basis **G2**.

| ID | Case | Also |
|---|---|---|
| 004.g2-cmd | empty `cmd` | §1.3 |
| 004.g2-pattern | empty `pattern` — `grep -e ''` would match every line | **C19** |
| 004.g2-FE | `fixed` + `extended` (`-F -E`): grep itself answers 2 | **C18** |
| 004.g2-lL | `filesOnly` + `filesWithoutMatch` | **C18** — grep accepts both, last-flag-wins |
| 004.g2-hH | `noFilename` + `withFilename` | **C18** |
| 004.g2-argv-empty | a refused build leaves `${inst}_argv` EMPTY, so nothing stale can run | §2.2 |
| 004.g2-halves | each half of a refused pair on its OWN is fine | boundary |

### F. G3 — `maxCount` goes through `kk.isInt` (8)

| ID | Case | Class | Basis |
|---|---|---|---|
| 004.g3-abc | `maxCount = abc` → rc 2 | contract | **G3** |
| 004.g3-neg | `maxCount = -1` → rc 2 — grep 3.0 takes `-m -1` as *no limit*, silently | contract | **C17** |
| 004.g3-space | `maxCount = '1 2'` → rc 2; never re-split into two words | representation | **C17** |
| 004.g3-hex | `maxCount = 0x10` → rc 2 (`kk.isInt` takes digits only) | contract | **C17** |
| 004.g3-zero | `maxCount = 0` is ACCEPTED (`>= 0`) and emits `-m 0` | boundary | **G3** |
| 004.g3-08 | `maxCount = 08` emits `-m 8` — the normalised `$__KK_INT` | contract | **C17** |
| 004.g3-plus5 | `maxCount = +5` emits `-m 5`, and the property still reads `+5` | contract | **C17** — the OUTVAR form would have written through the property nameref |
| 004.g3-empty | `maxCount = ''` (the default) emits NO `-m` at all | boundary | §1.3 |

### G. G4 — a flag-shaped pattern is data; the derived `-0` (13)

| ID | Case | Class | Basis |
|---|---|---|---|
| 004.g4-dashv | pattern `-v` lands AFTER `-e` and is searched, not parsed | representation | **G4** |
| 004.g4-help | pattern `--help` is data too | representation | **G4** |
| 004.g4-dashe | pattern `-e` next to a real `-v` flag stays in its slot | representation | **G4** |
| 004.g4-newline | a pattern with a NEWLINE is one word (grep's own multi-pattern form) | representation | **G4** |
| 004.nul-lZ | `nullOut = 1` + `filesOnly = 1` DERIVES `nul = 1` — the sinks get `-0` | contract | **C10**, §2.7 |
| 004.nul-LZ | `nullOut = 1` + `filesWithoutMatch = 1` derives it too | contract | §2.7 |
| 004.nul-cZ | `nullOut = 1` + `countOnly = 1` does NOT derive it (records stay `\n`-framed) | contract | **C10** — measured: `a.txt\0 2\n` |
| 004.nul-Z | `nullOut = 1` alone (normal output) does NOT derive it | contract | **C10** |
| 004.nul-idempotent | the derivation is IDEMPOTENT — dropping `filesOnly` takes `-0` back off | contract | **P2-F1** — a set-only rule was not idempotent; `_nulDerived` records who set it |
| 004.nul-manual | a MANUAL `nul = 1` with `nullOut = 0` is the caller's and survives | contract | §2.7 |
| 004.nul-manual-nonderiving | a MANUAL `nul = 1` survives a non-deriving `nullOut`/`countOnly` build too | contract | §2.7 |
| 004.nul-not-claimed | a DERIVING build does not CLAIM a `nul = 1` the caller already set: through `-lZ` and back off, `nul` stays `1` and `_nulDerived` never leaves `0` | contract | **P3-F1** — the bookkeeping must tell derived from caller-set from off, and was only telling two apart; red-first 1 FAIL of 184 |
| 004.crlf-untouched | `crlf` is never touched by `buildArgv` | contract | §2.7 — buildArgv mutates no other state |

---

## 005_Search.sh — TGrep against GNU grep on a real tree (P2) — 53 cases

### Z. the gate and the tree (2)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.gnu-banner | the `grep` on PATH is GNU grep | tool-behaviour | **D4**, **C14** — a non-GNU grep is on PATH on this box |
| 005.fixture | the fixture tree is in place (space, newline and leading-`-` names, UTF-8, CRLF, NUL, a subdir, real symlinks) | representation | §4, **C7** |

### A. G5 — no match is an ANSWER (6)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 005.g5-count | count, lastRc | rc 1, RESULT 0, `lastRc` 1 | contract | **G5**, §2.4 |
| 005.g5-each | each | rc 1 and the callback is NEVER called | contract | **G5** |
| 005.g5-toarray | toArray | rc 1, RESULT 0, the array EMPTIED | contract | **G5** |
| 005.g5-first | first | rc 1 with RESULT `''` | contract | **G5** |
| 005.g5-silent | all | no match says NOTHING, switch on or off — raw 1 is an answer, not an error | contract | **G5**, §1.2 |
| 005.g5-run | run | rc 1 and prints nothing | contract | **G5** |

### B. G6 — the regex dialect (4)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.g6-ere-bad | `extended = 1` with pattern `(` → rc 1, `lastRc` 2, ONE line | tool-behaviour | **G6**, §2.4 |
| 005.g6-bre-literal | the SAME pattern with `extended` off is a LITERAL `(` — rc 0, one hit | tool-behaviour | **C6** — the first draft had this backwards |
| 005.g6-fixed | `fixed = 1` (`-F`) makes `(` literal too | tool-behaviour | **G6** |
| 005.g6-ere-good | `extended = 1` with a valid ERE `(needle\|zebra)` matches | tool-behaviour | **G6** |

### C. G7 — `-Z` framing (4)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.g7-lZ | `filesOnly` + `nullOut`: a name with a SPACE and one with a NEWLINE both survive | representation | **G7**, §2.7 |
| 005.g7-l-noZ | `filesOnly` WITHOUT `nullOut` splits the newline name — why `-Z` exists | boundary | **G7** |
| 005.g7-cZ | `countOnly` + `nullOut` does NOT derive `-0` (records stay `\n`-framed) | tool-behaviour | **C10** |
| 005.g7-LZ | `filesWithoutMatch` + `nullOut` derives `-0` too and names the MISS | representation | **G7** |

### D. G8 — recursion (7)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.g8-dir-no-r | a DIRECTORY operand without `recursive` → rc 1, `lastRc` 2, zero records | boundary | **G8**, **C4** |
| 005.g8-dir-r | the SAME instance with `recursive = 1` finds the tree | tool-behaviour | **G8** |
| 005.g8-search-r | `TGrep.search PATTERN DIR` implies `-r` — byte-identical to `grep -r -e P -- DIR` | cross-check | **C4**, §2.5 |
| 005.g8-search-nopath | `TGrep.search` with NO path → rc 2, prints nothing, one line | contract | §2.5 — `grep -r` with none would search the CWD |
| 005.g8-search-nopat | `TGrep.search` with an EMPTY pattern → rc 2 and runs nothing | contract | **C19** |
| 005.g8-search-nomatch | `search` on a pattern nothing matches → rc 1 and silent | contract | **G5** |
| 005.g8-search-seq | `search` deletes its throw-away instance and bumps `__TG_SEQ` | contract | **C13**, §2.5 |

### E. G9 — the three forms (1)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.g9-three-forms | `search \| TPipe.each` under `lastpipe` == `TPipe.each -- search` == `g.each` with `recursive = 1`: same records, same order, same callback state | cross-check | **G9**, README §7 |

### F. G10 — the partial-failure deviation (3)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 005.g10-toarray | toArray, lastRc | good + MISSING + good → rc 1, RESULT = the REAL count, `lastRc` 2, records kept | contract | **C11**, §2.4 — the named deviation |
| 005.g10-count-each | count, each | the same on the same operands — everything that arrived is kept | contract | **C11** |
| 005.g10-one-line | toArray | the partial-failure path emits exactly ONE line of ours; grep's own passes through | contract | §1.2 |

### G. G11 — a nested `search` (2)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.g11-each | `g.each` whose callback runs `TGrep.search` — both complete, `g` survives | boundary | **C13**, **G11** |
| 005.g11-pipe | a nested `search` inside a `TGrep.search`-fed `TPipe.each` callback | boundary | **G11** |

### H. G12 — `-r` and a real directory symlink (3)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.g12-no-descend | `-r` does NOT descend a directory symlink (that is why it is never `-R`) | tool-behaviour | **G12**, **C7** — real NTFS symlink via `kt_make_symlink` |
| 005.g12-named-dir | a directory symlink NAMED on the command line IS followed even under `-r` | tool-behaviour | **G12** |
| 005.g12-named-file | a FILE symlink named on the command line is read through | tool-behaviour | **G12** |

### I. CRLF (3)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.crlf-stripped | a record from a CRLF file carries NO CR — grep stripped it, not us | tool-behaviour | **C8**, §2.6 |
| 005.crlf-binary | `binary = 1` (`-U`) shows the CR | representation | **C8** |
| 005.crlf-both | `binary = 1` + `crlf = 1` is the byte-faithful pass that still trims | representation | §2.6 |

### J. every remaining typed option, against the bare tool (15)

Class `cross-check` / `tool-behaviour`, basis **G1** + the option's own row in
README §1, except where noted.

| ID | Case |
|---|---|
| 005.j-i | `ignoreCase` → `-i` |
| 005.j-v | `invert` → `-v` (the lines that do NOT match) |
| 005.j-w | `wordRegexp` → `-w` — a partial word does not match (`boundary`) |
| 005.j-x | `lineRegexp` → `-x` — the WHOLE line must match |
| 005.j-n | `lineNumber` → `-n` (`1:alpha needle here`) |
| 005.j-o | `onlyMatching` → `-o` — one record per MATCH, not per line |
| 005.j-m | `maxCount = 1` → `-m 1`: one hit, then grep stops |
| 005.j-include | `include` → `--include=*.txt` (note.log is skipped) |
| 005.j-exclude | `exclude` → `--exclude=*.log` |
| 005.j-excludedir | `excludeDir` → `--exclude-dir=sub`: nothing under `sub/` is listed |
| 005.j-h | `noFilename` → `-h` (two operands, no `FILE:` prefix) |
| 005.j-H | `withFilename` → `-H` (ONE operand, the prefix forced on) |
| 005.j-z | `nullData` → `-z`, with a MANUAL `nul = 1` for the sink (§2.7) |
| 005.j-addarg | an `addArg` extra reaches grep verbatim — the un-modelled-option hatch (§1.4 item 5) |
| 005.j-stdin | an instance with NO path reads STDIN — documented, not a bug (§6) |

### K. binary files (3)

| ID | Case | Class | Basis |
|---|---|---|---|
| 005.k-record | a file with a NUL yields the `Binary file … matches` RECORD, rc 0 | representation | **C11**, §1.4 item 7 |
| 005.k-a | `addArg -a` turns it back into text — the documented escape hatch | tool-behaviour | §1.4 item 7 |
| 005.k-binary-files | `addArg --binary-files=text` does the same | tool-behaviour | §1.4 item 7 |

---

## 006_Contract.sh — the kcl contract for TGrep (P2, one case added at tutil P4) — 49 cases

### 0. source integrity (7)

| ID | Case | Class | Basis |
|---|---|---|---|
| 006.parse | the unit source parses (`bash -n`) | contract | §4 |
| 006.openquote | no single-quoted `printf` format is left open at end of line | contract | §4 |
| 006.inline-cr | no member body carries an inline `$'\r'` | bash-convention | §6 — it does not survive `declare -f`/`eval` |
| 006.no-this | no internal member call is spelled `$this.NAME` | contract | **C1**, §2.2 |
| 006.ctor-parent | the CONSTRUCTOR calls `parent.constructor grep`, never `inherited` | contract | **C2**, §2.1 |
| 006.dtor-inherited | the DESTRUCTOR frees `${inst}_paths` and then chains with `inherited` | contract | §2.1 — the rewrite that bites constructors does not apply here |
| 006.no-shadow | no `var` shadows a TUtil or kklass member name | contract | **C16**, §1.2 |

### Z. the gate (1)

| ID | Case | Class | Basis |
|---|---|---|---|
| 006.gnu-banner | the `grep` on PATH is GNU grep | tool-behaviour | **D4**, **C14** |

### 1. `set -eu` — the instance and BOTH TPipe forms (19)

Each case runs in a CHILD script under `set -eu` with the unit freshly sourced;
the child must end rc 0, print exactly `OK` and write nothing to stderr. Class
`contract` throughout.

| ID | Case | Basis |
|---|---|---|
| 006.eu-load | the unit loads under `set -eu` | §1.4, §1.6 |
| 006.eu-load2 | it loads TWICE — every re-source guard holds (tgrep → tutil → tpipe → kklass) | §1.4 |
| 006.eu-each | `g.each` on a matching instance | §1.3 |
| 006.eu-form2 | form 2: `TPipe.each CB -- "${argv[@]}"` with the argv TGrep built | README §7 |
| 006.eu-form2-search | form 2 with `TGrep.search` as the producer command | §2.5 |
| 006.eu-form1 | form 1: a REAL pipe under `shopt -s lastpipe` | tpipe F2 |
| 006.eu-funcs | every func sink on a matching instance | §2.3 |
| 006.eu-tolist | `toList` into a kklass instance with an `.Add` | **C21** |
| 006.eu-nomatch | NO MATCH (raw 1) — rc 1, the child survives, nothing on stderr | **G5** |
| 006.eu-greperror | a GREP ERROR (raw 2: a directory without `recursive`) — rc 1, no abort | **G8**, **C12** |
| 006.eu-partial | PARTIAL failure (a missing operand among good ones) — rc 1, records KEPT | **C11**, **G10** |
| 006.eu-refused | a REFUSED build (`-F` and `-E` together) — rc 2, nothing runs, no abort | **G2** |
| 006.eu-emptypat | an EMPTY pattern — rc 2 from every runner, no abort | **C19** |
| 006.eu-maxcount | a bad `maxCount` — rc 2, no abort | **G3** |
| 006.eu-search-nopath | `TGrep.search` with no path — rc 2, no abort, nothing printed | §2.5 |
| 006.eu-run | `run` streams and the raw rc is readable afterwards | §1.1 deviation |
| 006.eu-delete | `delete` on an instance that never ran anything | §1.9 |
| 006.eu-stdin | an instance reading STDIN (no path) under `set -eu` | §6 |
| 006.eu-cmdsubst | the `$( )` position: a func sink prints its value exactly ONCE | **P1-F1** |
| 006.subshellok | **D6 final Q9**: `g.subshellOk = 1` silences TPipe's subshell warning through two frames of wrapper (the child's stderr must be empty), while the same `$(g2.toArray A2)` without it carries the verbatim `Warning: TPipe.toArray: the array A2 is filled inside a subshell (BASH_SUBSHELL=1) — …` line | **D6 final Q3/Q9**, tutil PLAN P4.2 |

### 2. the debug switch (21)

`tg_dbg` counts OUR lines (`Error:` / `Warning:`) and the tool's (`grep: …`)
separately. Class `contract`; each `check_one` asserts exactly one line of ours
**and** complete silence with the switch off.

| ID | Case | Basis |
|---|---|---|
| 006.dbg-FE-each | rc 2: `-F` + `-E`, through `each` | **G2** |
| 006.dbg-FE-count | rc 2: `-F` + `-E`, through `count` | **G2** |
| 006.dbg-lL | rc 2: `-l` + `-L` | **C18** |
| 006.dbg-hH | rc 2: `-h` + `-H` | **C18** |
| 006.dbg-maxcount | rc 2: a bad `maxCount` | **C17** |
| 006.dbg-pattern | rc 2: an empty `pattern` | **C19** |
| 006.dbg-cmd | rc 2: an empty `cmd` | §1.3 |
| 006.dbg-search | rc 2: `TGrep.search` with no path | §2.5 |
| 006.dbg-out | rc 2: `toArray` with a bad out-name — TUtil's check, inherited | §1.7 |
| 006.dbg-dir | grep raw 2 (a directory without `recursive`) → rc 1 and one line | **G8** |
| 006.dbg-ere | grep raw 2 (an unmatched `(` under `-E`) → rc 1 and one line | **G6** |
| 006.dbg-missing | grep raw 2 (a missing operand among good ones) → rc 1 and one line | **G10** |
| 006.silent-ok-count | rc 0: a successful search says NOTHING | §1.2 |
| 006.silent-ok-each | rc 0: `each` on a hit says NOTHING | §1.2 |
| 006.silent-ok-toarray | rc 0: `toArray` on a hit says NOTHING | §1.2 |
| 006.silent-nomatch-count | rc 1: NO MATCH is an answer and says NOTHING | **G5** |
| 006.silent-nomatch-each | rc 1: `each` on no match says NOTHING | **G5** |
| 006.silent-nomatch-first | rc 1: `first` on no match says NOTHING | **G5** |
| 006.silent-search-hit | rc 0: `TGrep.search` that matched says NOTHING | §2.5 |
| 006.silent-search-miss | rc 1: `TGrep.search` that matched nothing says NOTHING | **G5** |
| 006.dbg-names-tgrep | the `grep exited` line names **TGrep**, and grep's OWN line is left alone | §1.2, §1.4 item 2 |

---

## 007_Bench.sh — the P3.1 performance gates (P3) — 9 cases

The real gates are measured by `../bench.sh` on an idle machine (README §9);
this file asserts the same shapes with a **10×** ceiling, because the two sides
of these ratios do not inflate together under the threaded runner — grep is its
own process and roughly doubles, while the wrapper's share is bash work in the
contended shell and has been seen to grow tenfold (a first threaded run measured
4.18× where the next measured 1.16×). The corpus is 2000 lines, and every timed
shape is **interleaved** with its baseline and compared by **median**, because
one process start in twenty takes 200 ms on this platform for reasons outside
this repo.

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 007.gnu-banner | — | the `grep` on PATH is GNU grep; without it every timed case below is a loud SKIP and the count is unchanged | tool-behaviour | **D4**, **C14** |
| 007.gate-search | search | `TGrep.search` costs at most 10× a bare `grep -r` over the same tree, and both find the same 21 hits | perf | §5 P3.1 (idle: 1.17× / 1.23×, gate 1.3×) |
| 007.ctor-cost | Create, Destroy | `TGrep.new` + `.delete` under 50 ms — the construction IS the search delta | perf | §2.5 (idle: ~2.5 ms; ~3.0 ms threaded) |
| 007.argv-runs-nothing | buildArgv, argv | 200 `buildArgv`/`argv` calls with `cmd` pointed at a counting function invoke it ZERO times, leave `$BASHPID` unchanged, and produce the 11 words of the pinned order | contract | §1.2, §1.5 |
| 007.argv-constant | argv | the 22-option build stays constant-cost: after 200 rebuilds it is still 11 words | boundary | §2.2 |
| 007.gate-count | count | `g.count` costs at most 10× `grep -c` on the same tree and counts the same 21 records | perf | §5 P3.1 (idle: 1.47× / 1.50×) |
| 007.gate-countonly | countOnly, toArray | `countOnly = 1` delivers grep's OWN per-file numbers in 2 records (compared as a SET — grep's walk order is not ours to pin) at most 10× `grep -c` | perf | README §9 (idle: 1.09× / 1.10×) |
| 007.fork-sinks | each, toList, toArray, count, first | the callback and `.Add` run in THIS process; all five sinks agree on the one record and `first` returns it | contract | §1.5 |
| 007.fork-builders | buildArgv, argv, paths, addArg, clearArgs, mapRc, lastRc, run, search | the seven builder members, `run` and `search` all leave `$BASHPID` untouched — the only fork per call is grep itself | contract | §1.5 |
