# TRegEx — upstream Delphi API reference

Source of truth: Delphi `System.RegularExpressions.TRegEx` (Embarcadero DocWiki:
<https://docwiki.embarcadero.com/Libraries/en/System.RegularExpressions.TRegEx>).
Delphi's `TRegEx` mirrors .NET `System.Text.RegularExpressions.Regex`; where the
DocWiki is terse the .NET spec is the tiebreaker. FPC ships a source-compatible
implementation in `packages/vcl-compat/src/system.regularexpressions.pp` — its
engine is **PCRE2**, whereas this port's engine is bash **POSIX ERE**. This
document maps every public member; the *dialect* differences (ERE vs PCRE) are
catalogued separately in [`ERE-vs-PCRE.md`](ERE-vs-PCRE.md).

Upstream declaration shape (abridged):

```pascal
TRegEx = record            // a VALUE type in Delphi
  constructor Create(const Pattern: string; Options: TRegExOptions = []);
  // instance + static (class) overloads of each:
  function  IsMatch(const Input: string): Boolean;
  class function IsMatch(const Input, Pattern: string; Options: ...): Boolean; static;
  function  Match(const Input: string): TMatch;
  function  Matches(const Input: string): TMatchCollection;
  function  Replace(const Input, Replacement: string): string;
  function  Replace(const Input: string; Evaluator: TMatchEvaluator): string;
  function  Split(const Input: string): TArray<string>;
  class function Escape(const Str: string; UseWildCards: Boolean = False): string; static;
end;
```

## kcl mapping conventions

- **Static class.** kcl exposes only the class-function surface (`TRegEx.isMatch`
  …). The instance form `TRegEx.Create(pattern)` is **wontfix**: bash caches
  compiled patterns internally, so an instance would add dispatch cost and
  nothing else.
- **No match objects.** `TMatch` / `TGroup` / `TMatchCollection` / `NextMatch`
  become `RESULT` / `RESULT_INDEX` / `RESULT_LENGTH` / `RESULT_GROUPS` globals
  and nameref array fills (kcl house style).
- **Index is 0-based** (`RESULT_INDEX`), following .NET; Delphi's `TMatch.Index`
  is **1-based** — subtract 1 when porting.
- Booleans → rc `0`/`1`; invalid pattern → rc `2`.

---

## Class functions

### IsMatch
```pascal
class function IsMatch(const Input, Pattern: string; Options): Boolean; static;
```
→ **`TRegEx.isMatch text pattern [flags]`** — rc 0 match / 1 no-match / 2 invalid.
A pure predicate; sets no globals. FPC `TestClassIsMatch(Options)`.

### Match
```pascal
class function Match(const Input, Pattern: string; Options): TMatch; static;
```
→ **`TRegEx.match text pattern [flags]`**. On a match: `RESULT`=`TMatch.Value`,
`RESULT_INDEX`=`TMatch.Index − 1` (0-based), `RESULT_LENGTH`=`TMatch.Length`,
`RESULT_GROUPS`=the numbered sub-groups (`TMatch.Groups[1..]`, **text only** —
`BASH_REMATCH` carries no per-group Index/Length). FPC `TestMatch` (first match
`abba` at Delphi index 5 → our 4, group 1 `bb`).

- `TMatch.Success` → rc (0 = matched).
- `TMatch.NextMatch` (iteration) → not applicable; use `matches` for all matches.
- Start-position overload `Match(Input, StartPos, Length)` → **wontfix** (bash
  matches the whole subject; no windowed match).

### Matches
```pascal
class function Matches(const Input, Pattern: string; Options): TMatchCollection; static;
```
→ **`TRegEx.matches text pattern outTexts [outOffsets|-] [flags]`**. Fills the
`outTexts` array with every match (lossless), optionally `outOffsets` with
0-based absolute offsets; `RESULT`=`TMatchCollection.Count`. An **empty match
advances one character** (PCRE/.NET rule). FPC `TestMatches` (count 3).

### Replace
```pascal
function Replace(const Input, Replacement: string): string;                 // string template
function Replace(const Input: string; Evaluator: TMatchEvaluator): string;  // callback
// + Count overloads
```
→ **`TRegEx.replace text pattern repl [maxCount|-] [flags]`** (template) and
**`TRegEx.replaceCb text pattern cbName [maxCount|-] [flags]`** (callback).
Replaces **all** by default; `maxCount` caps replacements. Sets `RESULT` and
**body-echoes** the result. FPC `TestReplace` (`a(b*)a` → `c` gives
`xyz c c c zyx`), `TestReplaceCount`, `TestReplaceEval`, `TestReplaceEvalCount`.

Replacement template grammar (`$`-form, Delphi/.NET):

| Token | Meaning |
|---|---|
| `$$` | literal `$` |
| `$&`, `$0` | whole match |
| `$1`…`$9` | numbered group (single digit) |
| `${n}` | numbered group *n* (any width) |
| out-of-range / unknown `$x` | kept literal |

`\1` and `\{1}` (accepted by FPC's lower-level `TPerlRegEx`) are **not** group
references here — only `$` is special; `&` and `\` are literal (see
[`ERE-vs-PCRE.md`](ERE-vs-PCRE.md) §2.3). The callback receives
`cbName "<wholeMatch>" "<g1>" …` and sets `REPLY`.

### Split
```pascal
class function Split(const Input, Pattern: string; Options): TArray<string>; static;
// + Count / StartPos overloads
```
→ **`TRegEx.split text pattern outArr [maxCount|-] [flags]`**. Fills `outArr`
with the pieces between matches; captured groups are **interleaved**;
leading/trailing/consecutive empties are **kept**; no match → the whole text as
one piece; `maxCount` limits pieces (Delphi/Perl "limit"). `RESULT`=piece count.
FPC `TestSplitAll` / `TestSplitLimit`.

### Escape
```pascal
class function Escape(const Str: string; UseWildCards: Boolean = False): string; static;
```
→ **`TRegEx.escape text`** — backslash-quotes the ERE metacharacters
`\ . ^ $ * + ? ( ) [ ] { } |` so the result matches `text` literally; sets
`RESULT` and body-echoes. The Delphi `UseWildCards` mode (DOS `?`/`*` → regex)
and its control-character escaping (`CRLF`→`\r\n`) are **not** ported — this is
plain ERE-metacharacter escaping only (see [`ERE-vs-PCRE.md`](ERE-vs-PCRE.md) §2.4).

---

## Options (`TRegExOptions`)

| Delphi option | kcl |
|---|---|
| `roIgnoreCase` | flag `i` (scoped `nocasematch`, deterministic, ambient restored) |
| `roMultiLine` | **wontfix** — bash `=~` has no per-line `^`/`$` mode; split into lines first |
| `roExplicitCapture`, `roSingleLine`, `roIgnorePatternSpace`, `roCompiled`, `roNotEmpty` | **wontfix** — no ERE analogue / nothing to precompile (see PLAN.md §1, [`ERE-vs-PCRE.md`](ERE-vs-PCRE.md) §1) |

## Not ported (engine dialect — wontfix)

Lazy quantifiers, lookaround, named groups, pattern backreferences, `\d \w \s`
shorthands (use POSIX classes), inline modifiers. Each is documented and, where
testable, pinned as a divergence test. Full reasoning: [`ERE-vs-PCRE.md`](ERE-vs-PCRE.md).
