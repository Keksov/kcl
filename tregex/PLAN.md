# TRegEx → bash port plan (kcl/tregex)

**Roadmap position:** 2/7 (owner priority order, 2026-07-12).
**Source of truth:** Delphi `System.RegularExpressions.TRegEx` (record with static class functions; DocWiki API). Secondary reference only: FPC `packages/regexpr/src/regexpr.pas` (TRegExpr, Sorokin engine) — its API is non-standard and its engine is NOT ported (see §2.1).
**Target:** `kcl/tregex/tregex.sh` — kklass Pascal-DSL **static** class `TRegEx` (model: tpath/tfile/dateutils/math — no instances; TRegEx in Delphi is used almost exclusively through its static functions).
**Ledger:** `kcl/tregex/tregex_ledger.json`.
**Workflow:** phase → dual-bash tests → full master sweep → STOP → "go"; commits gated; no unit edits while a sweep is in flight.
**Conventions:** as `kcl/tdictionary/PLAN.md` §2.2–2.4/§6 (RESULT/rc, debug-only stderr, `$()` caveat, `__prefix` locals, TEST_COVERAGE_NOTES protocol).

---

## 1. Scoping analysis

**The load-bearing decision: API shape is TRegEx, engine is bash `[[ =~ ]]` (POSIX ERE + BASH_REMATCH).**
Implementing a regex engine in bash would be a hundred times slower than the builtin and
thousands of lines; the builtin engine is C, fork-free, and already caches compiled
patterns. The price is honesty about the dialect: **ERE is not PCRE**. Every delta is
documented (README table + tests that pin the DOCUMENTED divergent behavior), never
silently papered over.

### Ported

| Delphi (static) | bash | Notes |
|---|---|---|
| `TRegEx.IsMatch(Input, Pattern[, Options])` | `TRegEx.isMatch text pattern [flags]` | rc 0/1 |
| `TRegEx.Match(Input, Pattern[, Options])` | `TRegEx.match text pattern [flags]` | first match → RESULT=text, RESULT_INDEX (0-based), RESULT_LENGTH, RESULT_GROUPS array |
| `TRegEx.Matches(...)` | `TRegEx.matches text pattern outTexts [outOffsets] [flags]` | global scan; nameref array fills (lossless); RESULT=count |
| `TRegEx.Replace(Input, Pattern, Replacement[, Options])` | `TRegEx.replace text pattern replacement [maxCount] [flags]` | replaces ALL by default (Delphi semantics); `$0…$9`, `$$` in replacement |
| `TRegEx.Split(Input, Pattern[, Options])` | `TRegEx.split text pattern outArr [flags]` | nameref fill; RESULT=count |
| `TRegEx.Escape(Str)` | `TRegEx.escape text` | quotes ERE metacharacters `\ ^ $ . [ ] | ( ) * + ? { }` |
| `roIgnoreCase` | flag char `i` | via scoped `nocasematch` (§2.3) |
| capture groups | `RESULT_GROUPS` / `BASH_REMATCH` copy | numbered only |

Match-evaluator (callback) overload of Replace: ported as a bash extra —
`TRegEx.replaceCb text pattern cbName [maxCount] [flags]`, cb receives the match +
groups and echoes/returns the replacement (exact contract pinned at P0).

### NOT ported (wontfix — engine dialect, each documented in README delta table)

1. **Lazy quantifiers** `*?` `+?` `??` — ERE is greedy-only (leftmost-longest).
2. **Lookaround** `(?=)` `(?!)` `(?<=)` `(?<!)` — no ERE analog.
3. **Named groups** `(?<name>…)` and `TMatch.Groups['name']` — numbered groups only.
4. **Backreferences in the pattern** (`\1`) — undefined in POSIX ERE (GNU accepts some;
   NOT portable — documented as unsupported).
5. **Shorthand classes** `\d \w \s \b` as PCRE guarantees — POSIX spellings
   `[[:digit:]] [[:alnum:]_] [[:space:]]` documented; GNU `\b \< \>` work in practice
   on both target bashes (probed at P0, documented as GNU-glibc-specific).
6. **Inline modifiers** `(?i)`, free-spacing `(?x)`, `roExplicitCapture`,
   `roIgnorePatternSpace`, `roCompiled` (nothing to precompile — bash caches internally),
   `roNotEmpty`.
7. **`roMultiLine`** — bash `=~` has no per-line `^`/`$` mode. Documented; line-oriented
   work should split first (kcl has the tools).
8. **PCRE alternation semantics** (leftmost-FIRST) — ERE picks leftmost-LONGEST;
   a dedicated test PINS the divergence so it is never a surprise.
9. **TRegEx instance/record form, TMatch/TGroup/TMatchCollection objects,
   NextMatch/Result(...)** — replaced by RESULT_* variables and array fills (kcl house
   style; enumerator-object protocol is dispatch overhead with no gain).
10. **NUL bytes** in subject/pattern (bash language limit).

---

## 2. Design decisions

### 2.1 Engine = `[[ =~ ]]`, patterns always via variable
The pinned kcl idiom (math P7 incident): the pattern is ALWAYS passed through a local
variable — `local __re="$2"; [[ $text =~ $__re ]]`. A quoted RHS would switch to literal
matching; an inline `(a|b)` parses as bash grouping. This also makes user patterns with
spaces/metachars safe. Invalid pattern → `[[ =~ ]]` returns rc=2 → mapped to **rc=2**
(preserved as-is, distinct from "no match" rc=1; documented; debug-msg under
VERBOSE_KKLASS=debug).

### 2.2 Match offset without engine support
bash `=~` reports no positions — only BASH_REMATCH texts. Offset recovery idiom:
`__pre=${text%%"${BASH_REMATCH[0]}"*}; RESULT_INDEX=${#__pre}` (first literal occurrence
of the matched text). **Caveat (documented + P0 probe matrix):** with anchors/word
boundaries (`^ $ \b \< \>`) the matched text can occur earlier than the anchored match
position; for the unanchored patterns that dominate real usage the recovery is exact
(same text at an earlier position would itself have matched — ERE substring matching is
context-free without anchors). `matches`/`replace`/`split` iterate on the REMAINDER
(absolute offset = consumed + local offset), which keeps global scans consistent under
the same caveat.

### 2.3 `i` flag via scoped nocasematch — fork-free save/restore
`shopt -s nocasematch` affects `=~`. Idiom: `local __had=0; shopt -q nocasematch && __had=1;
shopt -s nocasematch; …; (( __had )) || shopt -u nocasematch` — no `$()` (no fork), restore
guaranteed on every return path (single exit point or trap-free discipline; pinned at P0).

### 2.4 Global scan loop (`matches`, `replace`, `split`)
Loop: match against the current remainder; record absolute offset; advance past the match.
**Empty-match rule** (PCRE/.NET convention, pinned by test): an empty match advances the
scan by ONE character (no infinite loop); an empty match at end-of-string terminates.
`maxCount` optional arg bounds replacements (Delphi Replace has no count in the static
form — bash extra, documented).

### 2.5 Replacement grammar
`$0…$9` substitute groups, `$$` = literal `$`; unknown `$x` kept literally (Delphi/.NET
behavior pinned at P0 from DocWiki). No sed involved — pure bash assembly from
BASH_REMATCH, so `& \ /` in replacements are LITERAL (a delta table row vs sed
expectations, tested).

### 2.6 Static class, no compiled objects
Nothing to precompile: bash caches compiled regexes keyed by pattern string internally.
`TRegEx.Create(pattern)` instance form is therefore pointless dispatch — wontfix (§1.9).

---

## 3. Pinned semantics / P0 probe matrix

| # | Question | Expectation | Pin method |
|---|---|---|---|
| S1 | `.` matches newline in `=~`? | yes (subject is one string, not lines) | P0 probe BOTH bashes |
| S2 | Empty pattern `''` | match-everything (rc=0, empty match) vs rc=2 | P0 probe |
| S3 | Invalid pattern rc | 2 | P0 probe + pinned test |
| S4 | `nocasematch` affects `=~` and `==` both | yes → scoped set/restore | P0 probe |
| S5 | Offset recovery exactness w/o anchors | exact | P0 adversarial probe set (repeated substrings) |
| S6 | Offset recovery with `^ $ \b` | documented caveat cases | P0 probe → README table |
| S7 | `\b \< \>` availability | GNU glibc yes, both bashes | P0 probe |
| S8 | Alternation leftmost-longest | `(a|ab)` on "ab" → "ab" (ERE) vs PCRE "a" | pinned divergence test |
| S9 | Locale effect on `[a-z]`, case folding of non-ASCII under `i` | current-locale dependent | P0 probe → documented |
| S10 | BASH_REMATCH unset groups (`(a)|(b)`) | empty string for non-participating group | P0 probe (5.2 vs 5.3!) |
| S11 | Replacement `$…` grammar edge cases | §2.5 | DocWiki/.NET reading + tests |
| S12 | Split semantics: captured groups included? leading/trailing empties? | .NET: captures included, empties kept | P0 DocWiki pin → tests |

## 4. Parity & test model

No FPC/fpcunit seeds exist. Basis: DocWiki examples for TRegEx members + .NET Regex
documented behavior where Delphi defers, ERE-divergence table rows as EXPLICIT pinned
tests (the delta IS the spec), plus kcl torture conventions: exotic subjects (newlines,
globs, quotes, `$(...)`, unicode), exotic replacements, empty strings everywhere,
zero-fork PATH='' on all entry points, dual-bash (S10 especially). Every test gets a
TEST_COVERAGE_NOTES.md row (all non-FPC by construction).

## 5. Phases

- **P0 — probe matrix + design pin.** Run S1–S12 probes on 5.2.37 AND 5.3.9; record
  results in the ledger; finalize offset-recovery caveat wording, flags set, replacement
  grammar; skeleton + runner; baseline re-measure. STOP.
- **P1 — isMatch / match / escape.** Core single-match path + RESULT_* contract +
  groups copy; escape() char set complete; tests incl. torture + zero-fork. Sweep gate. STOP.
- **P2 — matches / split.** Global scan loop + empty-match rule + nameref fills;
  split semantics per S12. Sweep gate. STOP.
- **P3 — replace / replaceCb.** Replacement assembler ($-grammar), maxCount, callback
  form. Sweep gate. STOP.
- **P4 — docs, bench, closeout.** README (API + THE DELTA TABLE), docs/TRegEx.md
  (upstream Delphi reference per kcl docs convention), bench.sh (dispatch overhead vs raw
  `=~`, matches() scaling on N occurrences, replace throughput), TEST_COVERAGE_NOTES
  finalized, ledger COMPLETE, final sweep. STOP.

## 6. Bash traps to respect

1. Pattern in a variable, ALWAYS (`local __re=`); never inline `(|)`, never quoted RHS.
2. `nocasematch` save/restore without `$()` (fork); restore on EVERY return path.
3. BASH_REMATCH is global and volatile — copy to RESULT_GROUPS immediately, before any
   further `[[ =~ ]]` (including ones hidden in called helpers).
4. `kk._return ""` on fail paths of funcs (kklass trailer trap).
5. Empty-match infinite-loop guard (§2.4).
6. Offsets are BYTE offsets in the C locale sense only if LC_ALL forced; default =
   character offsets in the current locale — pick ONE at P0 (leaning: character offsets,
   locale-as-is; document).
7. Subject strings with trailing newlines: RESULT lossless via direct call (never `$()`).

## 7. Deliverables

`kcl/tregex/`: tregex.sh, PLAN.md, tregex_ledger.json, README.md (incl. ERE-vs-PCRE
delta table), docs/TRegEx.md, bench.sh, TEST_COVERAGE_NOTES.md, tests/001…+tests.sh.
