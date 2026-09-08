# kcl/tregex — TRegEx for bash

Delphi `System.RegularExpressions.TRegEx`'s **API**, running on bash's
`[[ $s =~ $re ]]` **engine** (POSIX ERE via glibc `regexec`) — C-speed,
fork-free, patterns cached by bash internally. A **static** kklass class (no
instances): the whole surface is class functions, same as Delphi's usage.

> **ERE is not PCRE.** The FPC/Delphi `TRegEx` runs on **PCRE2**; this port runs
> on **POSIX ERE**. The API shape is identical and byte-exact where the dialects
> agree (proven against FPC's own tests — see *FPC parity* below), but the
> engine languages differ. Every divergence is documented **and** pinned by a
> test. Full catalogue: [`docs/ERE-vs-PCRE.md`](docs/ERE-vs-PCRE.md).

## Quick start

```bash
source kcl/tregex/tregex.sh

# predicate
if TRegEx.isMatch "$line" '^[0-9]+'; then echo "starts with a number"; fi

# single match — read the RESULT* globals (call DIRECTLY, not via $())
TRegEx.match "2026-07-12" '([0-9]+)-([0-9]+)-([0-9]+)'
echo "$RESULT"                 # 2026-07-12   (whole match)
echo "$RESULT_INDEX"           # 0            (0-based!)
echo "${RESULT_GROUPS[1]}"     # 07           (2nd numbered group)

# global scan — fills a nameref array, RESULT=count
nums=(); TRegEx.matches "$line" '[0-9]+' nums
echo "found $RESULT numbers: ${nums[*]}"

# scalar-returning members ALSO body-echo, so $() is ergonomic
safe=$(TRegEx.escape "a.b*c")      # a\.b\*c
out=$(TRegEx.replace "$csv" ',' ';')

# split (nameref fill) + callback replace
parts=(); TRegEx.split "a,b,c" ',' parts
wrap() { REPLY="<$1>"; };  TRegEx.replaceCb "$s" '[0-9]+' wrap
```

## The return contract

For a kklass **static** class the two member kinds differ on stdout: a
`static func` echoes `$RESULT` on *every* call, a `static proc` is silent. All
members here are `static proc`, so:

- **Multi-value / rc / array members** (`isMatch`, `match`, `matches`, `split`)
  are **silent**: they set the `RESULT*` globals and/or fill a nameref array.
  **Call them directly** — a `$()` subshell runs in a child and every global /
  array fill is lost to the parent.
- **Scalar string members** (`escape`, `replace`, `replaceCb`) additionally
  **body-echo** their one result, so both `x=$(TRegEx.escape …)` and
  `TRegEx.escape …; x=$RESULT` work.

Results:

| Global | Set by | Meaning |
|---|---|---|
| `RESULT` | all | matched text / result string / count |
| `RESULT_INDEX` | `match` | **0-based** offset (Delphi is 1-based — subtract 1) |
| `RESULT_LENGTH` | `match` | `${#matched}` in the ambient locale |
| `RESULT_GROUPS` | `match` | numbered sub-groups (`BASH_REMATCH[1..]`; text only) |

Return codes: **0** match / **1** no-match / **2** invalid pattern (bash's own
diagnostic is suppressed; a note appears under `VERBOSE_KKLASS=debug`).

## API

| Member | Returns | Notes |
|---|---|---|
| `TRegEx.isMatch text pattern [flags]` | rc 0/1/2 | pure predicate; writes no globals |
| `TRegEx.match text pattern [flags]` | `RESULT*` | first match; offset via prefix-strip (§ caveat) |
| `TRegEx.matches text pattern outTexts [outOffsets\|-] [flags]` | `RESULT`=count | global scan; fills text array (+ optional absolute offsets) |
| `TRegEx.split text pattern outArr [maxCount\|-] [flags]` | `RESULT`=count | pieces between matches; captured groups interleaved; empties kept; `maxCount` limits pieces |
| `TRegEx.replace text pattern repl [maxCount\|-] [flags]` | `RESULT` + echo | replace-ALL default; `maxCount` caps replacements |
| `TRegEx.replaceCb text pattern cbName [maxCount\|-] [flags]` | `RESULT` + echo | callback form (below) |
| `TRegEx.escape text` | `RESULT` + echo | quotes ERE metacharacters |

- **`flags`**: `i` = case-insensitive, and that is the **only** flag. `''` and
  `-` are the placeholders that let you pass a later positional; **anything
  else is `rc 2` and the member does nothing** (a malformed call, kcl contract
  §1.2). Until P7 the test was `*i*`, so `Multiline` silently turned
  case-insensitivity on and every other word was silently ignored.
  The flag is deterministic — it *fully* decides case sensitivity (a no-`i`
  call is case-sensitive even if the caller set `shopt -s nocasematch`) — and
  the caller's ambient `shopt` is restored on every path, rejected flags
  included.
- **`-` placeholder**: to pass `flags` without the optional 4th argument, use `-`
  (e.g. `TRegEx.matches "$s" "$re" out - i`).
- **Replacement grammar** (`replace`): `$$`→`$`, `$&`/`$0`→whole match,
  `$1`…`$9`→group, **`$10`…`$99`→group *n* when that group exists** (.NET's
  rule: the longest digit run that names a real group wins, so `$10` with 11
  groups is group 10, and with 2 groups it is group 1 followed by a literal
  `0`), `${n}`→group *n* (any width); an out-of-range or unknown `$x` is kept
  **literal**; `&` and `\` (sed metacharacters) are **literal** — only `$` is
  special.
- **Callback** (`replaceCb`): invoked as `cbName "<wholeMatch>" "<g1>" "<g2>" …`
  and must set `REPLY` to the replacement (fork-free; do not echo). A callback
  must not call `TRegEx.*` itself — the scan's group scratch is in scope.
- **Output-array names** are validated: a plain identifier that is not one of
  the framework's reserved names. `RESULT`, `RESULT_INDEX`, `RESULT_LENGTH`,
  `RESULT_GROUPS`, `REPLY`, `IFS`, `this`, `__inst__`, `__class__` and anything
  starting with `__kk_`, `__KK_`, `__tre_` or `__trx_` are refused with
  **rc 2**, and nothing is written. Before P7 a bad name printed a bash
  diagnostic, returned rc 0, and a reserved one bound the caller's array to the
  unit's own scratch.
- **`maxCount`** is validated the same way: a non-integer (or an
  injection-shaped `x[$(cmd)]`) is **rc 2**, never evaluated.

### `$( )` capture strips trailing newlines

`escape`, `replace` and `replaceCb` set `RESULT` **and** body-echo, so both
access paths work — but they are not identical. Command substitution removes
*all* trailing newlines, which is the shell's behaviour, not the unit's:

```bash
TRegEx.replace $'a\n\n' "a" "b" >/dev/null;  printf '%q\n' "$RESULT"   # $'b\n\n'
printf '%q\n' "$(TRegEx.replace $'a\n\n' "a" "b")"                     # b
```

Interior newlines survive both paths. If the trailing newlines matter, read
`RESULT` after a direct call.

## ERE-vs-PCRE deltas (summary)

The three most likely to bite when porting Delphi code (full list in
[`docs/ERE-vs-PCRE.md`](docs/ERE-vs-PCRE.md)):

| | PCRE (Delphi/FPC) | this port (POSIX ERE) |
|---|---|---|
| **Match index** | 1-based | **0-based** (subtract 1) |
| `\d \w \s`, lazy `*?`, lookaround, named groups, `(?i)` | supported | **wontfix** — use `[[:digit:]]` etc.; restructure |
| Alternation | leftmost-**first** (`a\|ab`→`a`) | leftmost-**longest** (→`ab`) |
| `.` vs newline | excludes `\n` by default | **matches** `\n` |
| Anchors in `matches`/`replace`/`split` | absolute (`\G`) | **re-anchor per remainder** (bash has no `\G`) |
| Replacement group refs | `$1` and `\1`, `\{1}` | `$`-form only (`\1` is literal) |
| Match objects | `TMatch`/`TMatchCollection`/`NextMatch` | `RESULT*` globals + nameref arrays |

### Match offsets, and the zero-length anchor delta

Offsets are recovered by prefix-strip (`${text%%"$matched"*}`), which is
**exact for unanchored patterns** — the overwhelming majority.

Two documented deltas:

1. For an anchored pattern whose matched *text* recurs earlier, the reported
   index is the earlier position (`match "ab ab" 'ab$'` → index 0, not 3).
2. A **zero-length** match carries no position information at all, so an
   anchored empty pattern (`$`, `^`, `\b`, `\<`, `\>`) reports offset 0 in
   every remainder *and the scan does not stop where .NET would*:
   `matches "abc" '$'` is **4** matches here against 1 in .NET, and
   `replace "abc" '$' '!'` is `!a!b!c!` against .NET's `abc!`.
   Use anchored patterns with `isMatch`/`match`, not with the scanning members.

Both are pinned by `tests/011_T3_T4_LocaleAndAnchors.sh` and tabulated in
[`docs/ERE-vs-PCRE.md`](docs/ERE-vs-PCRE.md) §4. Detecting (2) would need a
match offset bash does not expose, so R12 (owner, 2026-09-06) keeps it
documented rather than emulated.

### Locale

The regex engine and `${#…}` both follow the ambient locale **and agree with
each other**. Under an empty or `C` locale the engine matches **bytes**, so
`match "héllo wörld" "w.rld"` misses; under `C.UTF-8`/`en_US.UTF-8` it matches
and the index/length are in characters. kcl requires UTF-8 (`kcl/README.md`
§1.6): the unit exports `LC_CTYPE=C.UTF-8` at load time when `LC_ALL`,
`LC_CTYPE` and `LANG` are *all* empty, and never overrides a locale the caller
chose.

### `escape` cost (measured)

`escape` is 14 whole-string `${s//x/\x}` substitutions with the **backslash
first** (every later substitution introduces backslashes, and a second pass
over them would double-escape). That is ~25× faster than the per-character
loop it replaced — 50 000 characters went from 14.3 s to ~0.6 s — but it is
still not linear: bash's own `${var//pat/rep}` is quadratic on both 5.2.37 and
5.3.9 (one substitution over 10/20/40/80 kB: 11/48/183/712 ms). No pure-bash
implementation escapes that; for megabyte inputs, escape once and cache.

### Scan cost (measured)

`matches`/`split`/`replace` re-match the **remainder** and copy it past each
match, because bash cannot start a match at an offset. That makes a scan
O(n·k) in the text length and match count: on this machine `replace` over
1 500 characters with 500 matches costs ~0.19 s and over 6 000 characters with
2 000 matches ~2.4 s (≈13×, against 4× for a linear scan). It is inherent to
the engine, not an accident; for a very large corpus with very many matches,
reach for a single `[[ =~ ]]` loop or an external tool. `tests/013` pins the
curve so a future change cannot make it quietly worse.

## FPC parity

FPC ships a Delphi-compatible `TRegEx` in `packages/vcl-compat`
(`system.regularexpressions.pp`, over PCRE2) with fpcunit tests. Its
**dialect-compatible** cases are cross-checked in
[`tests/008_FpcParity.sh`](tests/008_FpcParity.sh) (adjusting the 1-based index
to 0-based and `\s`→`[[:space:]]`) — all green, confirming this port matches the
FPC oracle wherever ERE and PCRE agree.

## Honest positioning (measured)

From `bash bench.sh`, MSYS2 (5.2.37 / 5.3.9); the engine is the C builtin, so
everything is fork-free:

| Path | Cost | Note |
|---|---|---|
| raw `[[ $s =~ $re ]]` inline | ~7 µs | the engine itself |
| `TRegEx.isMatch` | ~118 µs | + kklass static-proc dispatch + flag validation |
| `TRegEx.match` | ~139 µs | + offset recovery + group copy |
| `TRegEx.escape` (43-char) | ~112 µs | 14 substitutions (was ~470 µs, a char loop) |
| `TRegEx.matches` | ~117 µs / occurrence | scan cost, ≈linear in the count |
| `TRegEx.replace` / `split` | ~0.14–0.17 ms / occurrence | scan + assembly |

P7 (2026-09-08) moved two of these: `escape` is 4× faster (T6), and
`isMatch`/`match` cost ~12 µs more because the flag word is now validated
instead of being matched with `*i*` (T5).

The dispatch wrapper costs ~80 µs over the raw builtin — negligible for
occasional matching, but for a tight inner loop over a huge corpus prefer a
direct `[[ =~ ]]`. `tregex` is for structured, correct, TRegEx-shaped regex
work with honest dialect semantics, not for being the fastest possible `grep`.

## Tests

`tests/001…014` — 246 cases, all green on bash 5.2.37 **and** 5.3.9:
wiring/contract, isMatch, match (offsets/groups/deltas), escape, flags+fork-free,
matches, split, **FPC parity (008)**, replace/replaceCb, the kcl contract (010),
and the P7 review regressions — locale + zero-length anchors (011, T3/T4),
strict flags + output-array validation (012, T5/T8), `escape`/scan scaling
(013, T6/T7), trailing-newline capture + two-digit group refs (014, T9/T10).
Coverage rationale per case in [`TEST_COVERAGE_NOTES.md`](TEST_COVERAGE_NOTES.md).
