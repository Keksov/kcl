# tstringhelper — Free Pascal `TStringHelper`, ported to bash

`string` is a **static** class (a namespace): there is nothing to instantiate,
every member is called as `string.<member>`.

```bash
source kcl/tstringhelper/tstringhelper.sh

string.trim "  hello  "          # direct call: prints NOTHING
printf '%s\n' "$RESULT"          # -> hello

parts=()
string.split "a,b,c" "," parts   # RESULT = 3, parts = (a b c)

if string.contains "$s" "@"; then ... fi     # predicates answer with rc
```

**Upstream reference:** FPC 3.2.2 —
`rtl/objpas/sysutils/syshelph.inc` (the `TStringHelper` declaration) and
`syshelp.inc` (the implementation), plus `sysstr.inc` for the SysUtils
routines the helper delegates to (`Trim`, `AnsiQuotedStr`, `TryStrToBool`,
`StrToInt`, `StringReplace`, `IsDelimiter`, `LastDelimiter`),
`rtl/inc/sstrings.inc` for `Val` and `rtl/inc/astrings.inc` for
`Copy`/`Delete`/`Insert`. `docs/TStringHelper.md` is the upstream Delphi/FPC
reference dump and describes members this port does not have.

---

## 1. The contract

This unit follows [`kcl/README.md`](../README.md) section 1 in full.

| Rule | Here |
|---|---|
| **Return** (1.1) | A **direct call prints nothing** and leaves the value in `RESULT`; inside `$( )` the value is printed exactly once, so `v=$(string.trim "$s")` keeps working. Implemented as `static proc` + `string._ret` — see below. |
| **Errors** (1.2) | rc 1, `RESULT=""`, nothing on stdout or stderr; a diagnostic only under `VERBOSE_KKLASS=debug`. |
| **Malformed call** (1.2, 1.7) | rc 2 — a reserved or non-identifier output-array name, an unknown `TStringSplitOptions` token. |
| **Booleans** (1.3) | The **exit status** is the answer; `RESULT` also carries `true`/`false` so `$(string.isEmpty x)` keeps working. Under `set -e` call them from `if`, `&&`/`\|\|` or `!`. |
| **`set -eu`** (1.4) | The unit loads and runs under `set -eu`; pinned by `tests/060_Contract.sh`. |
| **Numbers** (1.5) | Every index, count and width goes through `kk.isInt` before it reaches `(( ))`. `string.substring hello 'a[$(touch pwn)]'` is rc 1, not a command execution. |
| **Locale** (1.6) | UTF-8 is part of the contract: the members count and slice **characters**. The unit exports `LC_CTYPE=C.UTF-8` when `LC_ALL`, `LC_CTYPE` and `LANG` are all empty. |
| **Output arrays** (1.7) | `split`, `toCharArray` and `copyTo` write into a caller array by nameref and return the count in `RESULT`. |
| **No forks** (1.8) | No member shells out — pinned structurally by `tests/060_Contract.sh` and `tests/061_TSH17_ReturnContract.sh`. |

**Why `static proc` and not `static func`.** kklass's *thin* static dispatcher
— the one a class without static variables receives — re-prints
`kk._return`'s value **unconditionally**, i.e. on a direct call too, so a
`static func` would echo on every call. The unit therefore uses `static proc`
plus a two-line local helper that is `kk._return`'s contract without that
printf (`kcl/README.md` 1.1; the same pattern as tpath/tfile/tdirectory).

**Reserved names.** `__tsh_*` is this unit's variable prefix. It is refused as
an output-array name, together with `RESULT`, `REPLY`, `IFS`, `this`,
`__inst__`, `__class__` and anything starting with `__kk_`/`__KK_`.

---

## 2. API

`SELF` is the string the member works on. Optional arguments are in brackets;
an omitted optional argument and an empty one mean the same thing except where
noted.

### Comparison and predicates (answer with rc, `RESULT` = `true`/`false`)

| Member | Notes |
|---|---|
| `string.equals A B` | exact equality |
| `string.contains SELF VALUE` | substring test |
| `string.startsWith SELF VALUE [true]` | third argument `true` = ignore case; an empty `VALUE` is **true** (`Result := L<=0`) |
| `string.endsWith SELF VALUE [true]` | an empty `VALUE` is **true** (`Result := L=0`) |
| `string.startsText SUB TEXT` | case-insensitive, FPC argument order; an empty `SUB` is **false** |
| `string.endsText SUB TEXT` | case-insensitive, FPC argument order; an empty `SUB` is **false** |
| `string.isEmpty SELF`, `string.isNullOrEmpty SELF` | |
| `string.isNullOrWhiteSpace SELF` | FPC's whitespace set: every code point ≤ 32 |
| `string.isDelimiter SELF INDEX DELIMS` | false outside `[0, Length)` and for an empty set |
| `string.toBoolean SELF` | FPC `TryStrToBool`; a value that is neither a number nor `True`/`False` is a conversion **error** (rc 1, `RESULT=""`) |

### Comparison returning −1 / 0 / 1

`string.compare A B`, `string.compareOrdinal A B`, `string.compareText A B`
(case-insensitive), `string.compareTo A B`.

### Searching (0-based; −1 = not found)

| Member | Notes |
|---|---|
| `string.indexOf SELF VALUE [START] [COUNT]` | `START` defaults to 0, `COUNT` to `Length`. **`indexOf SELF ''` is −1** (FPC 3.2: `Pos('')` = 0). A negative `START` or `COUNT` is rc 1 (see difference 10). |
| `string.indexOfAny SELF ANYOF [START] [COUNT]` | `ANYOF` is a **set of characters**; an empty set never matches |
| `string.indexOfAnyUnquoted SELF ANYOF QSTART QEND [START] [COUNT]` | skips quoted regions; `QSTART == QEND` toggles, otherwise they nest |
| `string.lastIndexOf SELF VALUE [START] [COUNT]` | `START` is the inclusive index of the last character a match may **end** on (default `Length-1`); `COUNT` is a lower bound counted back from it (default `Length`) |
| `string.lastIndexOfAny SELF ANYOF [START] [COUNT]` | same window rule, character set |
| `string.lastDelimiter SELF DELIMS` | the last character of the set in the whole string |
| `string.countChar SELF CHAR` | |

### Editing

| Member | Notes |
|---|---|
| `string.replace SELF OLD NEW [FLAGS]` | **without `FLAGS` every occurrence is replaced** (FPC `Replace(Old,New)` = `[rfReplaceAll]`); *with* a `FLAGS` argument only what it names applies, so an empty `FLAGS` means the first occurrence only. Tokens: `rfReplaceAll`, `rfIgnoreCase`. An empty `OLD` returns `SELF`. |
| `string.substring SELF START [LEN]` | FPC `Copy` clamping: a negative start reads from the beginning, a non-positive length is empty, a start past the end is empty |
| `string.remove SELF START [COUNT]` | FPC `Delete` clamping: nothing is removed when `START+1` is outside `[1, Length]` or `COUNT ≤ 0` |
| `string.insert SELF INDEX VALUE` | index ≤ 0 prepends, index ≥ `Length` appends |
| `string.padLeft SELF WIDTH [PAD]`, `string.padRight` | `PAD` defaults to a space |
| `string.trim SELF`, `string.trimLeft`, `string.trimRight` | strip every character with a code **≤ 32** (FPC `WhiteSpace = [#0..' ']`), so tab, CR, LF, VT, FF and the other C0 controls — but **not** DEL (#127) |
| `string.trimStart SELF CHARS`, `string.trimEnd SELF CHARS` | strip a **character set**; an empty set strips nothing |
| `string.join SEP VALUES...` | |
| `string.quotedString SELF [QUOTE]` | FPC `AnsiQuotedStr`: wraps in `QUOTE` (default `'`) and **doubles** every occurrence of it inside |
| `string.deQuotedString SELF [QUOTE]` | unchanged unless the string is ≥ 2 characters and starts and ends with `QUOTE`; then a doubled quote collapses to one and a lone quote disappears |
| `string.create CHAR COUNT` | `COUNT ≤ 0` gives `""` |
| `string.copy SELF` | identity |

### Output arrays

| Member | Notes |
|---|---|
| `string.split SELF SEP ARRAY [COUNT] [OPTIONS]` | fills `ARRAY`, `RESULT` = number of parts. `SEP` is one literal **string**; an empty `SEP` gives one part. `COUNT` is FPC's `ACount`: 0 = unlimited, and the parts beyond the limit are **discarded**, they do not become a last element. `OPTIONS` ∈ `None` (default), `ExcludeEmpty`, `ExcludeLastEmpty`. |
| `string.toCharArray SELF [START] [LEN] [ARRAY]` | with `ARRAY`: one character per element, `RESULT` = count. Without it the characters are joined with newlines in `RESULT`, which is what `$(string.toCharArray abc)` printed before. |
| `string.copyTo SELF SRCINDEX ARRAY DESTINDEX COUNT` | writes `COUNT` characters into `ARRAY[DESTINDEX…]`; a source range past the end is rc 1 |

### Conversion

| Member | Notes |
|---|---|
| `string.toInteger SELF` | FPC `StrToInt` (`Val`): leading spaces/tabs, an optional sign, an optional base prefix (`$`, `x`, `X`, `0x`, `0X` = hex; `%` = binary; `&` = octal), then digits of that base and nothing else. `3.9`, `42 `, `12abc` and `""` are **errors** (rc 1, `RESULT=""`), not 0. Range: signed 32-bit. |
| `string.toInt64 SELF` | the same grammar with the Int64 range |
| `string.toDouble SELF`, `string.toExtended`, `string.toSingle` | FPC `StrToFloat` = `Val(trim(S))`: an optional sign, digits, a fraction and an exponent, decimal point `.`. Anything else is rc 1. `inf`/`nan` are not accepted. |
| `string.parse VALUE` | identity — see "Differences" below |

### Case, size, misc

`string.toLower`, `string.toLowerInvariant`, `string.lowerCase`,
`string.toUpper`, `string.toUpperInvariant`, `string.upperCase`,
`string.length SELF`, `string.chars SELF INDEX` (rc 1 outside the string),
`string.getHashCode SELF`, `string.format FMT ARGS...`.

---

## 3. Differences from FPC

Everything here is deliberate and pinned by a test.

1. **`format` is bash `printf`, not Pascal `Format`.** The directives are
   printf's (`%s`, `%d`, `%5.2f`, `%%`), Pascal's argument indices (`%0:s`)
   are not supported, and printf's rule of **reusing the format while
   arguments remain** applies (`string.format '%s,' a b c` → `a,b,c,`). A
   format or argument printf rejects is rc 1 with an empty `RESULT`; printf's
   own diagnostic is captured, never leaked with a kklass line number.
   *The format is a trust boundary: do not pass untrusted input as the format.*
2. **`parse` is the identity.** FPC's `Parse` overloads turn a Pascal
   `Boolean`/`Integer`/`Extended` into its string form; in bash the argument
   already is that string, and `BoolToStr`'s `-1`/`0` would be actively
   misleading here.
3. **`compare`, `compareOrdinal`, `compareTo` compare the WHOLE strings.**
   FPC's `Compare(A,B)` is `Compare(A,0,B,0,Length(B),[])`, a *prefix*
   comparison over `min(Length(A),Length(B))` characters, so FPC answers 0 for
   `Compare('abc','ab')`. Ordering also uses the collation of the current
   locale, not byte order. (Recorded in `kcl_ledger.json` as `found_in_P5`.)
4. **`indexOfAnyUnquoted` scans `ACount` characters.** FPC computes its scan
   limit as `StartIndex+ACount-1`, one character short of `IndexOfAny`'s, so
   with the default `ACount` it never examines the **last** character of the
   string. The port scans the window `IndexOfAny` would.
5. **`lastIndexOfAny` clamps the scan position to the last character.** FPC
   indexes `Self[AStartIndex+1]` without a bounds check, which reads past the
   end of the string in Pascal.
6. **`chars` outside the string is rc 1.** FPC's `Chars[]` property has no
   bounds check at all.
7. **Integer range checks reject instead of truncating.** FPC's `Val` accepts
   a decimal literal up to the Int64 range and then lets it truncate into the
   destination type, and accepts a non-decimal literal up to 2⁶⁴−1 and
   sign-extends it. Here a value that does not fit the destination is rc 1;
   what *does* fit answers exactly as FPC does, including the sign extension
   of a non-decimal literal (`string.toInteger '$FFFFFFFF'` → −1).
8. **`getHashCode` is defined on CODE POINTS.** FPC's `fphash` walks the bytes
   of the string, so its answer for non-ASCII text depends on the encoding.
   The algorithm is FPC's — `h := int32((h shl 5) - h) xor c`, signed 32-bit —
   and for ASCII input the two agree exactly.
9. **`split` takes ONE separator string**, not FPC's `array of Char` /
   `array of string`, and no quote-character overloads. `string.split 'a, b'
   ', '` is two parts, not a split on `,` and ` ` separately.
10. **A negative index or count in the SEARCH family is rejected** — rc 1 with
    an empty `RESULT` — in `indexOf`, `indexOfAny`, `indexOfAnyUnquoted`,
    `lastIndexOf` and `lastIndexOfAny`. FPC's arithmetic there is undefined by
    accident: `IndexOf` clamps its window with `Copy` but still adds the *raw*
    `StartIndex` to the result, so `indexOf 'hello world' o -3` would answer 1
    and, with an explicit count, can even land on −1 — indistinguishable from
    "not found". Where FPC genuinely *defines* the clamping — `Copy` and
    `Delete`, i.e. `substring` and `remove` — it is reproduced exactly
    (difference 7 of the API table: `substring hello -3` is still `hello`).
11. **`endsText` and `startsText` are false for an empty subtext**, following
    `TStringHelper.EndsText` (`Result := (ASubText<>'') and …`). FPC's own
    `StrUtils.AnsiEndsText`/`AnsiStartsText` say the opposite
    (`(ASubText='') or …`), and `TStringHelper` has no `StartsText` at all, so
    the port takes the class function's rule for both. `startsWith`/`endsWith`
    are `TStringHelper` members with their own rule — `Result := L<=0`, i.e.
    an **empty value is true** — and that asymmetry is upstream's, not the
    port's.

## 4. Tests

```bash
bash kcl/tstringhelper/tests/tests.sh                    # the whole suite
bash kcl/tstringhelper/tests/tests.sh 061 --verbosity info
```

`060_Contract.sh` carries the kcl-wide contract, `061_TSH17_ReturnContract.sh`
the return/predicate/error contract member by member, `063_TSH04_Locale.sh`
the character semantics (with non-ASCII **before** the searched character) and
the locale self-heal, `066_TSH09_Performance.sh` the 10 KB performance gates.
