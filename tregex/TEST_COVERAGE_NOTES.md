# tregex — test coverage notes (all cases non-FPC by construction)

**Status: FINALIZED at P4 (2026-07-12).** Suite 001–009 = 190 cases, all green
on bash 5.2.37 AND true 5.3.9. P4 added README.md, docs/TRegEx.md,
docs/ERE-vs-PCRE.md, and bench.sh — `bench.sh` is a benchmark (its numbers live
in README.md/the ledger), not a test, so it adds no rows here.

Protocol (same as dateutils/math/tdictionary/tstopwatch): every **invented** test
case gets a row here; the **FPC-traceable** cases (008_FpcParity.sh) instead cite
their FPC procedure. CORRECTION (2026-07-12): the original claim "no FPC tests for
this API" was wrong — FPC ships a Delphi-compatible `TRegEx`
(`packages/vcl-compat/src/system.regularexpressions.pp`, over **PCRE2**) with
tests `utcregexapi.pas` / `utcregex.pas`. Its dialect-compatible subset is adopted
in 008; the PCRE↔ERE deltas it exposes are catalogued in `docs/ERE-vs-PCRE.md`. The **Basis**
column cites Delphi DocWiki member semantics, .NET `Regex` documented behavior
(tiebreaker), the POSIX ERE spec, or a P0 probe result (§ tregex_ledger.json
`probe_results`). Classes:

- **contract** — rc mapping, RESULT* globals, silent-vs-echo, dispatch, zero-fork;
- **behavior** — normal matching semantics the engine supports;
- **delta** — a DOCUMENTED ERE-vs-PCRE divergence, pinned so it is never a
  surprise (the delta IS the spec);
- **representation** — bash-specific: locale/`${#}` offset units, BASH_REMATCH
  copy timing, ambient `shopt` handling;
- **torture** — hostile subjects/patterns (quotes, globs, `$(...)`, newlines,
  unicode, empty, leading dash).

## 001 — wiring + return-contract mechanics

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 001.defined | all 7 | every declared member has a dispatcher after `build` | contract | kklass build wires declared members |
| 001.predicate | isMatch | dispatches as predicate (hit rc0 / miss rc1) | contract | DocWiki IsMatch → Boolean |
| 001.direct-result | match | a DIRECT call sets the RESULT global | contract | static-proc contract (P0 pin) |
| 001.direct-silent | match | a DIRECT call prints nothing to stdout | contract | static-proc is silent (P0 probe) |
| 001.no-subshell-leak | match | under `$()` the globals do NOT leak to the parent | contract | subshell semantics; call-direct rule |
| 001.escape-echo | escape | scalar members body-echo → `$()` captures the value | contract | owner P0 decision (math-style ergonomics) |
| 001.pending-stubs | matches/split/replace/replaceCb | pending members dispatch as stubs (sentinel RESULT) | contract | phase discipline (real bodies P2/P3) |
| 001.zero-fork | isMatch/match/escape | source + all 3 dispatch under `PATH=''` | contract | zero-fork house goal; `[[ =~ ]]`/shopt are builtins |

## 002 — isMatch

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 002.hit-miss | isMatch | substring hit rc0 / miss rc1 / full via `^…$` | behavior | DocWiki IsMatch |
| 002.invalid-rc2 | isMatch | `[` `(` `a{2,1}` leading-`*` trailing-`\` → rc2 | contract | P0 S3 (bash stderr suppressed) |
| 002.empty-rc2 | isMatch | empty pattern `''` → rc2 (NOT match-all) | delta | P0 S2 + owner decision (vs .NET match-empty) |
| 002.anchors | isMatch | `^`/`$` at string ends only; not mid-string | behavior | POSIX ERE |
| 002.dot-newline | isMatch | `.` matches `\n` (subject is one string) | delta | P0 S1 (vs PCRE/.NET default) |
| 002.no-multiline | isMatch | `^`/`$` never at `\n` boundaries | delta | P0 ADJ (roMultiLine wontfix) |
| 002.posix-classes | isMatch | `[[:digit:]] [[:space:]] [a-z] [^0-9]` | behavior | POSIX class support |
| 002.alternation | isMatch | `cat|dog` hit/miss | behavior | POSIX ERE alternation |
| 002.word-bound | isMatch | `\b…\b`, `\<…\>` whole-word; reject partial | delta | P0 S7 (GNU/glibc, not POSIX-portable) |
| 002.i-flag | isMatch | case-sensitive default; `i` insensitive; mixed | behavior | roIgnoreCase → nocasematch (S4) |
| 002.pattern-in-var | isMatch | spaces / escaped globs / `(a|b)` in the pattern var | representation | pinned kcl idiom (pattern always via var) |
| 002.torture | isMatch | subjects with `*?[]`, quotes, `$(...)`, backticks, unicode, leading-`-`, empty | torture | kcl torture convention |

## 003 — match (RESULT* contract, offsets, groups)

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 003.tuple | match | RESULT / RESULT_INDEX / RESULT_LENGTH for leading/mid/single/greedy | behavior | DocWiki Match (TMatch.Value/Index/Length) |
| 003.offset-exact | match | unanchored repeated-substring offsets exact (`xxabcabc`, `aaa`) | representation | P0 S5 (prefix-strip is exact w/o anchors) |
| 003.offset-caveat | match | `abc$` on `abcXabc` → index 0 not 4 (prefix-strip finds earlier copy) | delta | P0 S6 (documented anchored caveat) |
| 003.empty-match | match | `a*` on `zzz` → RESULT='' index 0 length 0 rc0 | behavior | empty-match at leftmost position |
| 003.longest | match | `a|ab` and `ab|a` on `ab` → `ab` | delta | P0 S8 (leftmost-LONGEST vs PCRE first) |
| 003.dot-newline | match | `a.b` on `a\nb` → whole (len 3) | delta | P0 S1 |
| 003.unicode-offset | match | `é` in `café` → text+offset robust; length is `${#}` ambient-locale | representation | P0 S9 (byte vs char per locale) |
| 003.groups | match | numbered groups → RESULT_GROUPS = BASH_REMATCH[1..]; 0 groups → empty | behavior | DocWiki TMatch.Groups (numbered only) |
| 003.nonparticipating | match | `(a)|(b)` on `b` → g1='' g2='b' | delta | P0 S10 (empty, indistinguishable from empty match) |
| 003.quantified-group | match | `(.)+` on `abc` → g1='c' (last iteration) | behavior | P0 ADJ3 (POSIX) |
| 003.reset | match | no-match rc1 / invalid rc2 → RESULT='' index -1 length 0 groups=() | contract | tuple reset discipline |
| 003.rematch-copy | match | RESULT_GROUPS survive a later failing isMatch (copy not alias) | representation | P0 ADJ (failed match clears BASH_REMATCH) |
| 003.i-original-case | match | `i` match returns the ORIGINAL-case matched text + groups | behavior | BASH_REMATCH holds subject text, not pattern |

## 004 — escape

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 004.each-meta | escape | each of `\ . ^ $ * + ? ( ) [ ] { } |` → single leading `\` | behavior | DocWiki Escape (ERE metaset) |
| 004.non-meta | escape | letters/digits/`-`/`_`/space/unicode/empty untouched | behavior | only ERE metachars are quoted |
| 004.all-metas | escape | full metachar salad escaped exactly | behavior | completeness of the metaset |
| 004.round-trip | escape+isMatch/match | escaped output matches the input LITERALLY; whole string at index 0 | cross-check | escape ∘ match identity |
| 004.no-over-match | escape+isMatch | escaped `a.c` rejects `aXc` (metachar truly neutralized) | cross-check | correctness of neutralization |
| 004.dual-contract | escape | `$()` body-echo == RESULT | contract | owner P0 decision |
| 004.torture-newline | escape | newline in subject kept verbatim, still round-trips | torture | non-metachar handling |

## 005 — i-flag + fork-free

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 005.i-control | isMatch | `i` present → insensitive, absent → sensitive | behavior | roIgnoreCase |
| 005.determinism | isMatch | a no-`i` call is case-SENSITIVE even when ambient `nocasematch` is ON | representation | flag fully controls (Delphi per-call semantics) |
| 005.restore-off | isMatch | ambient OFF restored after an `i` call | representation | fork-free save/restore (PLAN §2.3) |
| 005.restore-on | isMatch | ambient ON restored after a no-`i` call | representation | fork-free save/restore |
| 005.restore-invalid | match | ambient restored even on the invalid-pattern (rc2) path | representation | restore on EVERY return path |
| 005.i-match-groups | match | `i` match yields original-case text + groups | behavior | see 003.i-original-case |
| 005.in-process | match | global RESULT set in-process (no `$()` subshell wrapping) | contract | dynamic-scope propagation proof |
| 005.zero-fork | isMatch/match/escape | all 3 entry points complete under `PATH=''` (incl. i-flag path) | contract | zero-fork; builtins only |
| 005.shopt-intact | isMatch | i-flag toggling leaves unrelated shopts (extglob/nullglob) untouched | representation | scoped only to nocasematch |

## 006 — matches (global scan)

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 006.basic | matches | count in RESULT + lossless text array (digits/words/greedy) | behavior | DocWiki Matches |
| 006.no-match | matches | zero matches → count 0, empty array | behavior | empty collection |
| 006.empty-advance | matches | `x*` over `abc` → 4 empty matches; `Y*` mixed → `['','YY','','']` | behavior | .NET empty-match advance-by-one |
| 006.rc | matches | rc 0 (≥1) / 1 (none) / 2 (invalid) | contract | count-API rc convention |
| 006.offsets | matches | optional outOffsets = absolute positions | representation | prefix-strip offset accounting |
| 006.i-flag | matches | `-` offsets placeholder lets `i` be passed; case-insensitive count | contract | signature disambiguation (flags = arg 5) |
| 006.anchor-caveat | matches | `^.` on `abc` → `[a,b,c]` (re-anchors per remainder) | delta | remainder scan (no `\G` in bash) |
| 006.direct-required | matches | `$()` subshell discards the nameref fill | contract | call-direct rule |
| 006.torture | matches | newline-separated, quoted tokens, unicode, empty subject | torture | kcl torture convention |
| 006.zero-fork | matches | scan completes under `PATH=''` | contract | builtins only |

## 007 — split

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 007.core | split | drop delimiters (`a,b,c` → `[a][b][c]`) | behavior | .NET Regex.Split |
| 007.groups | split | captured groups INTERLEAVED (`a1b2c`/`([0-9])` → `a 1 b 2 c`) | behavior | S12 (.NET includes captures) |
| 007.empties | split | leading/trailing/consecutive empties KEPT (`,a,,b,` → 5 pieces) | behavior | S12 (.NET keeps empties) |
| 007.no-match | split | no delimiter → whole text as one piece | behavior | .NET Split no-match |
| 007.empty-match | split | `x*` over `abc` → `['','a','b','c','']` (absolute-position assembly) | behavior | .NET empty-match split |
| 007.delimiters | split | multichar / regex-class / whitespace-run delimiters | behavior | ERE delimiter patterns |
| 007.i-flag | split | case-insensitive delimiter | behavior | roIgnoreCase |
| 007.rc | split | rc 0 valid / 2 invalid (array cleared on invalid) | contract | error convention |
| 007.direct-required | split | `$()` subshell discards the fill | contract | call-direct rule |
| 007.round-trip | split | join(split(text, literal)) reconstructs text | cross-check | split ∘ join identity |
| 007.torture | split | newline delimiter, unicode pieces, quoted pieces | torture | kcl torture convention |
| 007.zero-fork | split | completes under `PATH=''` | contract | builtins only |
| 007.limit | split | maxCount caps pieces (retro; last piece = remainder) | behavior | Delphi/Perl Split limit; FPC TestSplitLimit |

## 008 — FPC parity (FPC-TRACEABLE; not "non-FPC")

Cross-checks against FPC's Delphi-compatible `TRegEx` (`utcregexapi.pas` /
`utcregex.pas`), fixture `'xyz abba abbba abbbba zyx'` / `'a(b*)a'`. Adjusted for
0-based index (`my=fpc-1`) and `\s`→`[[:space:]]`. Basis column = the FPC procedure.

| ID | Functions | Case | Basis (FPC proc) |
|---|---|---|---|
| 008.isMatch | isMatch | match true / +'xyz' false; +roIgnoreCase | TestClassIsMatch(Options) |
| 008.match | match | 'abba' idx 4(=fpc5-1) len 4 group1 'bb'; no-match empty; i→'ABBA' | TestMatch/NoMatch/ClassMatchOptions |
| 008.matches | matches | count 3 ['abba','abbba','abbbba'] offs [4 9 15]; i-flag | TestMatches/ClassMatchesOptions |
| 008.split | split | whitespace → 5 pieces; limit 2 → ['xyz','rest'] | TestSplitAll/TestSplitLimit |
| 008.replace | replace | all→'xyz c c c zyx'; count 2; i-flag; $1→'*bb*' | TestReplace/Count/ClassReplaceOptions/GroupDollar |
| 008.replaceCb | replaceCb | wrap each → '<…>'; +maxCount 2 | TestReplaceEval/EvalCount |

## 009 — replace / replaceCb (invented)

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 009.default | replace | replace-ALL default; literal repl; no-match unchanged | behavior | DocWiki Replace |
| 009.grammar | replace | `$0`/`$&`/`$1`/`${n}`/`$$`; out-of-range & unknown `$x` literal | behavior | .NET substitution grammar; PLAN §2.5 |
| 009.sed-literal | replace | `&` and `\` are LITERAL (only `$` special) | delta | vs sed expectations |
| 009.maxCount | replace | cap replacements (1/2/0=all) | behavior | Delphi Replace(count) |
| 009.i-flag | replace | case-insensitive vs sensitive default | behavior | roIgnoreCase |
| 009.empty-match | replace | `x*` inserts between chars → `-a-b-c-` | behavior | empty-match advance-by-one |
| 009.anchor-caveat | replace | `^` re-anchors per remainder → `>a>b>c>` (not `>abc`) | delta | remainder scan (no `\G`) |
| 009.torture | replace | newline/unicode/quotes/empty subject+replacement | torture | kcl torture convention |
| 009.invalid | replace | invalid pattern → rc2, text unchanged | contract | error convention |
| 009.echo | replace | `$()` body-echo == direct RESULT | contract | owner P0 (scalar member) |
| 009.cb-reply | replaceCb | callback sets REPLY; uppercases each match | contract | callback protocol |
| 009.cb-groups | replaceCb | callback receives groups as `$2..` | behavior | group passing |
| 009.cb-maxCount | replaceCb | maxCount limits callback invocations | behavior | Delphi Replace(eval,count) |
| 009.cb-empty | replaceCb | empty REPLY deletes the match | behavior | replacement semantics |
| 009.zero-fork | replace/replaceCb | complete under `PATH=''` | contract | builtins only |
