# TRegEx dialect report: bash POSIX ERE vs FPC/Delphi PCRE2

**Purpose.** `kcl/tregex` gives you Delphi's `System.RegularExpressions.TRegEx`
**API** but runs on a different **engine** than the real Delphi/FPC unit. This
document catalogues every difference, so the divergences are a known,
tested contract rather than a surprise. It is grounded in FPC's own test suite
(the oracle we cross-check against).

## The two engines

| | kcl/tregex | FPC `system.regularexpressions` (and Delphi) |
|---|---|---|
| Engine | bash `[[ $s =~ $re ]]` → **POSIX ERE** (glibc `regexec`) | **PCRE2** (unit source: *"this unit uses PCRE2"*) |
| Backing | C, in the shell, fork-free, patterns cached internally | libpcre2 |
| Match model | `RESULT*` globals + nameref arrays | `TMatch`/`TGroup`/`TMatchCollection` objects |

POSIX ERE and PCRE are genuinely different regex languages. The port implements
the TRegEx **shape** (`isMatch`/`match`/`matches`/`replace`/`split`/`escape`)
faithfully and is byte-exact with FPC wherever the two dialects agree — the
`tests/008_FpcParity.sh` cross-checks prove that on FPC's own fixture
(`'xyz abba abbba abbbba zyx'` / `'a(b*)a'`). Everything below is where they
*don't* agree.

FPC test files referenced (in `packages/vcl-compat/tests/`):
`utcregexapi.pas` (the `TRegEx` API) and `utcregex.pas` (the `TPerlRegEx` engine).

---

## 1. Engine-feature deltas — PCRE has it, ERE does not (wontfix)

Silently emulating these in bash would be slow and would lie about the engine;
each is documented and, where testable, pinned by a divergence test.

| Feature | PCRE / FPC | bash ERE (this port) | Use instead |
|---|---|---|---|
| Lazy quantifiers `*? +? ??` | non-greedy | greedy only (**leftmost-longest**) | restructure the pattern |
| Lookaround `(?=) (?!) (?<=) (?<!)` | supported | none | split the problem |
| Named groups `(?<n>…)`, `Groups['n']` | supported (FPC `TestNamedGroups`) | **numbered only** | use numbered groups |
| Backreference in pattern `\1` | supported | not portable in POSIX ERE | — |
| `\d \w \s` shorthands | supported (FPC `TestSplitAll` uses `\s`) | use POSIX `[[:digit:]] [[:alnum:]_] [[:space:]]` | POSIX classes |
| Inline modifiers `(?i) (?x)` | supported | none | the `i` flag arg |
| Multiline `^ $` (per line) | `roMultiLine` | none — `^ $` = whole-string ends only | split into lines first |

### Alternation order (pinned divergence)
- **PCRE: leftmost-FIRST.** `a|ab` on `"ab"` → `"a"`.
- **ERE: leftmost-LONGEST.** `a|ab` on `"ab"` → `"ab"` — regardless of branch order (`ab|a` also → `"ab"`).
- Pinned in `003_Match.sh` (`longest (a|ab)…`).

---

## 2. Convention deltas — same concept, different values

These are the ones most likely to bite a porter, because the code "works" but
the numbers/spellings differ.

### 2.1 Match index is 0-based here, 1-based in Delphi/FPC ⚠️
Delphi `TMatch.Index` (and FPC's) is **1-based**; this port returns **0-based**
`RESULT_INDEX` (the .NET `Regex` convention). FPC `TestMatch` asserts `'abba'`
at index **5**; we return **4**. Cross-check rule: `ours = fpc − 1`
(`008_FpcParity.sh` applies it explicitly).

| | FPC/Delphi | this port |
|---|---|---|
| First `'abba'` index | 5 | 4 |
| No-match index | 0 | −1 |

### 2.2 Groups: text only, no per-group offsets
FPC `TMatch.Groups[i]` carries `Value` **and** `Index`/`Length`. bash
`BASH_REMATCH` gives group **text only**, so `RESULT_GROUPS` has texts and no
positions. Also FPC's `Groups.Count` **includes group 0** (the whole match);
our `RESULT_GROUPS` holds **sub-groups only** (`BASH_REMATCH[1..]`), so for
`a(b*)a` FPC reports `Groups.Count = 2` while `${#RESULT_GROUPS[@]} = 1` (the
whole match is in `RESULT`).

### 2.3 Replacement grammar
Delphi/.NET use a `$`-grammar; FPC's lower-level `TPerlRegEx` *additionally*
accepts backslash forms. This port implements the **`$`-grammar only**:

| Token | This port | Notes |
|---|---|---|
| `$$` | literal `$` | |
| `$&`, `$0` | whole match | |
| `$1`…`$9` | group (single digit) | out-of-range → kept literal (`$9` → `"$9"`) |
| `${n}` | group *n* (any width) | out-of-range → kept literal |
| `\1`, `\{1}` | **literal backslash text** | FPC `TestReplaceGroupBackslash`/`Quoted` treat these as group 1 — **we do not** |
| `&`, `\` (sed) | **literal** | only `$` is special; a documented delta vs `sed` |

### 2.4 Escape
FPC `TRegEx.Escape(s, aUseWildCards)` has a DOS-**wildcard** mode (`?`→`(.)`,
`*`→`(.*)`) and escapes control characters to text (`CRLF`→`\r\n`). This port's
`escape` is **plain ERE-metacharacter quoting** — it backslash-quotes
`\ . ^ $ * + ? ( ) [ ] { } |` and leaves everything else (including real CR/LF
bytes) verbatim. No wildcard mode. (No FPC plain-escape case exists to
cross-check, so `escape` has invented coverage only, in `004_Escape.sh`.)

---

## 3. Architecture deltas — kcl house style

| Delphi/FPC | this port |
|---|---|
| `TMatch` / `TGroup` / `TMatchCollection` objects; `NextMatch` iteration | `RESULT` / `RESULT_INDEX` / `RESULT_LENGTH` / `RESULT_GROUPS` globals + nameref array fills |
| instance `TRegEx.Create(pattern)` | **static only** — bash caches compiled patterns internally, so an instance would be pure dispatch overhead |
| `Match(input, startPos[, length])` window | not supported (whole-subject match only) |
| results returned as objects | multi-value members are **silent, call-direct** (a `$()` subshell loses the globals); scalar members (`escape`/`replace`/`replaceCb`) additionally body-echo |

---

## 4. Global-scan deltas — a bash engine limit

`matches` / `replace` / `split` scan by re-matching the **remainder** and
advancing past each match (bash has no `\G`/previous-match anchor). Consequences:

- **Anchors re-anchor per remainder.** `^ $ \b \< \>` are relative to each
  remainder slice, not the whole string. Example (pinned in `009_Replace.sh`):
  `replace("abc", "^", ">")` → `">a>b>c>"` here, but `">abc"` in .NET (which
  anchors `^` once at the true start). Unanchored patterns — the overwhelming
  majority — scan exactly.
- **Offset recovery is prefix-strip.** A match's index is found via
  `${text%%"$matched"*}`; exact for unanchored patterns, but for `$`/`\b`
  anchored patterns whose matched *text* recurs earlier it reports the earlier
  position (probe S6, pinned in `003_Match.sh`).
- **Empty-match advance-by-one** (matches PCRE/.NET): an empty match advances
  the scan one character, so `matches("abc","x*")` yields 4 empty matches and
  `replace("abc","x*","-")` → `"-a-b-c-"`.

---

## 5. Locale deltas

Offsets and lengths are `${#…}` **in the ambient locale**. ASCII is exact
everywhere. For multibyte text the unit depends on the locale plumbing: under an
empty/`C` locale on MSYS2, bash `${#}` **byte**-counts while the regex engine
**char**-counts (they disagree); a full UTF-8 locale (`C.UTF-8`/`en_US.UTF-8`)
makes both char-count. Scan *correctness* is locale-independent (advance is by
string ops); only the reported numeric index/length carries the caveat. (Probe
S9.)

---

## 6. Reverse deltas — ERE differs from PCRE's *defaults* in our favour/otherwise

- **`.` matches newline.** In bash ERE the subject is one string and `.` spans
  `\n` (probe S1); PCRE's default excludes `\n` (needs `Singleline`).
- **`\< \>` word-edge anchors** work (GNU/glibc) in addition to `\b`; these are
  GNU extensions, not POSIX, and not standard PCRE spelling.

---

## 7. Gaps the FPC cross-check closed

- **`split` limit/count.** FPC `TestSplitLimit` (`Split(subject, 2)` →
  `['xyz', 'abba abbba abbbba zyx']`) exposed that our `split` lacked a count.
  Added: `split text pattern outArr [maxCount|-] [flags]` with Delphi/Perl
  "limit = max pieces" semantics (after `maxCount−1` splits the whole remainder
  becomes the last piece). Cross-checked in `008_FpcParity.sh`.

---

## Summary

The port is **API-faithful and value-exact on the shared dialect** (proven by
the FPC parity suite), and **honestly divergent** everywhere PCRE and POSIX ERE
differ. If you are porting Delphi regex code, the three things to check first:
1. **Index is 0-based** (subtract 1 from Delphi positions).
2. **PCRE-only features** (`\d`, lazy, lookaround, named groups) — rewrite with
   POSIX classes / restructure.
3. **Anchors in global operations** re-anchor per remainder.
