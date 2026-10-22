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

## 010 — the kcl contract (P1, 2026-09-06)

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 010.parse | — | `bash -n` on the unit + no unterminated `printf '` format | integrity | PLAN §4 (two mechanical sweeps corrupted sources) |
| 010.setu | all | loads, RE-loads and runs its main path under `set -eu` | contract | D7, X-SETU |
| 010.inj | split/replace | `maxCount` never reaches `(( ))` raw (canary file) | security | T2, D1 |
| 010.sete | match | a failing member returns control under `set -e` | contract | D7, T1 |

## 011 — locale and zero-length anchors (P7, 2026-09-08 — T3, T4/R12)

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 011.locale-utf8 | match | `C.UTF-8`: `w.rld` matches `wörld`, idx 6, len 5 | behavior | S9 |
| 011.locale-c | match | `LC_ALL=C`: the engine matches BYTES, `w.rld` MISSES; `w..rld` matches, len 6 | delta | T3 — the old docs claimed the opposite |
| 011.locale-heal | match | an empty environment self-heals to `LC_CTYPE=C.UTF-8` | contract | D6, §1.6 |
| 011.locale-respect | — | a locale the caller CHOSE is not overridden | contract | D6 |
| 011.offsets-utf8 | match/matches | offsets and lengths are CHARACTERS under UTF-8 | behavior | S9 |
| 011.anchor-scan | matches | `$` `^` `\b` `\<` `\>` each yield len+1 matches at 0..len; `x*` agrees with .NET | delta | T4/R12 — pinned, not fixed |
| 011.anchor-replace | replace | `$`→`!a!b!c!`, `^`→`>a>b>c>`, `\b`→`\|a\|b\| \|c\|d` (.NET: `abc!`, `>abc`, `\|ab\| \|cd\|`) | delta | T4/R12 |
| 011.anchor-split | split | `$` → `[][a][b][c][]`; `\b` → 6 pieces | delta | T4/R12 |
| 011.s6-offset | match | `match "ab ab" 'ab$'` reports index 0 (the true match is at 3) | delta | S6 |
| 011.unanchored | match/matches | unanchored offsets are EXACT (the other half of the delta) | behavior | S5 |
| 011.docs | — | the two corrected claims are present in `tregex.sh`, `docs/ERE-vs-PCRE.md` and `README.md` | docs | T3/T4 |

## 012 — strict flags and output-array validation (P7 — T5, T8)

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 012.flag-unknown | all 5 flag-taking members | 11 flag words (`Multiline`, `m`, `x`, `I`, `ii`, `-i`, …) → rc 2 | contract | T5, §1.2 |
| 012.flag-noop | matches/replace | a rejected flag performs NOTHING (arrays and text untouched) | contract | T5 |
| 012.flag-silent | isMatch | silent by default, speaks under `VERBOSE_KKLASS=debug` | contract | §1.2 |
| 012.flag-accepted | all | `i`, `''`, `-` and absent behave as documented | behavior | T5 |
| 012.flag-shopt | isMatch | the ambient `nocasematch` is restored after a REJECTED flag too | contract | S4 |
| 012.name-invalid | matches/split | 8 invalid names (incl. an injection shape) → rc 2, silent, nothing written | security | T8, §1.7 |
| 012.name-reserved | matches/split | 20 reserved names (`__tre_*`, `__trx_*`, `RESULT*`, `REPLY`, `IFS`, `this`, `__kk_*`) → rc 2 | contract | T8, §1.7 |
| 012.name-offsets | matches | argument 4 (the offsets array) is validated like argument 3 | contract | T8 |
| 012.name-state | matches | a rejected name leaves `RESULT=0` and no collateral writes | contract | T8 |
| 012.name-valid | matches | normal identifiers, incl. one that only LOOKS reserved, still work | regression | T8 |
| 012.maxcount | split/replace | a bad `maxCount` is rc **2**, not rc 1, and is never evaluated | contract | T2, §1.2 |

## 013 — escape and scan scaling (P7 — T6, T7)

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 013.esc-table | escape | 14 exact rows incl. `\`, `\`, `\.`, `.\` and the full metaset | behavior | T6 |
| 013.esc-roundtrip | escape/match | 17 literals match themselves, backslash-terminal included | behavior | T6 |
| 013.esc-speed | escape | >= 8x faster than the char loop it replaced, same output on 20 000 chars | perf | T6 (relative gate, PLAN §4) |
| 013.esc-50k | escape | 50 000 characters under 2 s (was 14.3 s) | perf | T6 |
| 013.esc-fork | escape | fork-free, no command substitution | contract | §1.8 |
| 013.scan-scale | replace | 4x the matches on 4x the text costs <= 24x (i.e. no worse than the remainder copy) | perf | T7 |
| 013.scan-2000 | matches/split | 2000 occurrences are all found and all pieces kept | behavior | T7 |
| 013.scan-copy | _replaceScan | the prefix-strip result is REUSED, not re-sliced (one copy per match, not two) | perf | T7 |

## 014 — capture caveat and two-digit group refs (P7 — T9, T10)

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 014.trailing-nl | replace/escape | `RESULT` keeps trailing newlines that `$( )` strips | delta | T9 |
| 014.interior-nl | replace | an interior newline survives both paths | behavior | T9 |
| 014.g10 | replace | with 11 groups `$10`/`$11` are groups 10 and 11 | behavior | T10 (.NET rule) |
| 014.g10-fallback | replace | with 2 groups `$10` is group 1 + literal `0`; `$12`/`$99` fall back one digit | behavior | T10 |
| 014.braces | replace | `${n}` unchanged, wins over the bare form, out-of-range stays literal | regression | S11 |
| 014.grammar | replace | the other 9 grammar rows unchanged | regression | S11 |
| 014.cb | replaceCb | the callback still receives the whole match and every group | regression | S11 |
| 014.docs | — | README documents the capture caveat and the `$10` rule | docs | T9/T10 |
