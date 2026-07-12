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

- **`flags`**: `i` = case-insensitive. Deterministic — the flag *fully* decides
  case sensitivity (a no-`i` call is case-sensitive even if the caller set
  `shopt -s nocasematch`), and the caller's ambient `shopt` is restored.
- **`-` placeholder**: to pass `flags` without the optional 4th argument, use `-`
  (e.g. `TRegEx.matches "$s" "$re" out - i`).
- **Replacement grammar** (`replace`): `$$`→`$`, `$&`/`$0`→whole match,
  `$1`…`$9`→group (single digit), `${n}`→group *n* (any width); an out-of-range
  or unknown `$x` is kept **literal**; `&` and `\` (sed metacharacters) are
  **literal** — only `$` is special.
- **Callback** (`replaceCb`): invoked as `cbName "<wholeMatch>" "<g1>" "<g2>" …`
  and must set `REPLY` to the replacement (fork-free; do not echo).
- **Reserved array names**: don't pass output arrays named `__trx_texts`,
  `__trx_offs`, or `__trx_out` (kklass nameref self-reference).

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

Match offsets use prefix-strip: **exact for unanchored patterns**; for `^ $ \b`
anchored patterns whose matched text recurs earlier, the reported index can be
the earlier position (documented caveat, pinned by a test).

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
| `TRegEx.isMatch` | ~80–90 µs | + kklass static-proc dispatch |
| `TRegEx.match` | ~95–120 µs | + offset recovery + group copy |
| `TRegEx.escape` (43-char) | ~0.4 ms | pure char loop |
| `TRegEx.matches` | ~115 µs / occurrence | scan cost, ≈linear |
| `TRegEx.replace` / `split` | ~0.12–0.17 ms / occurrence | scan + assembly |

The dispatch wrapper costs ~80 µs over the raw builtin — negligible for
occasional matching, but for a tight inner loop over a huge corpus prefer a
direct `[[ =~ ]]`. `tregex` is for structured, correct, TRegEx-shaped regex
work with honest dialect semantics, not for being the fastest possible `grep`.

## Tests

`tests/001…009` — 190 cases, all green on bash 5.2.37 **and** 5.3.9:
wiring/contract, isMatch, match (offsets/groups/deltas), escape, flags+fork-free,
matches, split, **FPC parity (008)**, replace/replaceCb. Coverage rationale per
case in [`TEST_COVERAGE_NOTES.md`](TEST_COVERAGE_NOTES.md).
