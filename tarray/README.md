# kcl/tarray — TArray (FPC TArrayHelper) for bash

Port of FPC rtl-generics `TArrayHelper<T>` (`generics.collections.pas`; Delphi
`System.Generics.Collections.TArray` is the same API household). A **static**
kklass utility — no instances, no state of its own: every member operates on a
**caller-named indexed array** via nameref, exactly like FPC's class functions
operate on your `TArray<T>` variable.

```bash
source kcl/tarray/tarray.sh

nums=(37 12 99 1 50)
TArray.sort nums -n                    # in place -> 1 12 37 50 99
TArray.binarySearch nums 50 -n         # rc 0; RESULT=3 (index)
TArray.min nums -n; echo "$RESULT"     # 1

files=("b name" $'we ird\nfile' "a name")
TArray.sort files                      # byte order, newline-safe, no fork
```

## Return contract

All members are `static proc` (silent — nothing on stdout). They mutate the
named array and/or set globals, so **call them directly**: a `$()` subshell
discards both the array writes and the globals.

| Global | Set by | Meaning |
|---|---|---|
| `RESULT` | search/min/max | found index (−1 miss) \| min/max value \| default |
| `RESULT_CANDIDATE` | binarySearch | `TBinarySearchResult.CandidateIndex` (miss ⇒ insertion point) |
| `RESULT_COMPARE` | binarySearch | last compare sign: `sign(array[candidate] − item)` |

rc: **0** ok/found/true · **1** not-found/false/rejected-input · **2** argument
error. Indices are **0-based** (FPC dynamic arrays are 0-based too — values map
1:1, no adjustment).

## API

| Member | Semantics |
|---|---|
| `TArray.sort arr [cmp\|-n] [start count]` | in-place **stable** sort; range form sorts only `[start, start+count−1]` (count≤1 no-op) |
| `TArray.binarySearch arr item [cmp] [start count]` | rc 0/1; RESULT + CANDIDATE + COMPARE (the `TBinarySearchResult` record, flattened). Precondition: sorted under the SAME comparator |
| `TArray.indexOf arr item [cmp]` | first occurrence (≡ `firstIndexOf`, as in FPC) |
| `TArray.firstIndexOf / lastIndexOf arr item [cmp]` | first / last occurrence, −1 miss |
| `TArray.contains arr item [cmp]` | rc 0 present / 1 absent |
| `TArray.min / max arr [cmp] [default]` | min/max **value**; empty → `default`, rc 1 |
| `TArray.copy src dst [srcIdx dstIdx] count` | strict FPC bounds: same array → rc 2; dst **not** auto-grown (pre-size it); count 0 no-op |
| `TArray.reverse src dst` | dst = reversed src via a temp — `reverse a a` (in-place) is safe; src untouched otherwise |
| `TArray.reverseInPlace arr` | bash extra = `reverse arr arr` |
| `TArray.concat dst src1 [src2 …]` | array **names**; empty sources skipped; dst may be a source |
| `TArray.compact arr` | bash extra: re-index sparse → dense 0..n−1 (the ONE place holes drop) |

**Dense contract:** methods expect indices `0..n−1` (the FPC data model).
Sparse arrays are undefined for sort/search — run `TArray.compact` first.
Associative arrays are rejected (rc 1). Don't pass arrays named `__ta_*`
(nameref self-reference).

## Comparators — three modes

| Mode | Select with | Order |
|---|---|---|
| **byte** (default) | nothing | `LC_ALL=C` strcmp — deterministic across machines; `0-9 < A-Z < a-z`. Locale collation is a deliberate NON-goal |
| **numeric** | `-n` | 64-bit integer by value; element shape `^-?[0-9]+$` enforced (violation → rc 1, array untouched — no silent lexicographic fallback); leading zeros fine (`007` compares as 7 **and stays `"007"`** in the array) |
| **custom** | a function name | your plain bash function, called `cmpFn a b` |

The custom comparator returns via **exit code** — never stdout (an echo would
need `$()` = one fork per comparison):

```bash
# rc 0: a < b     rc 1: a == b     rc 2: a > b
byLen() { (( ${#1} < ${#2} )) && return 0; (( ${#1} == ${#2} )) && return 1; return 2; }
words=(ccc a bb dddd)
TArray.sort words byLen                # -> a bb ccc dddd
```

**Stability is guaranteed:** equal elements keep their input order (FPC's
introsort leaves equal-order *unspecified*, so this is parity-compatible and
strictly stronger — proven by tagged-duplicate tests).

## Honest positioning vs `/usr/bin/sort` (measured)

From `bash bench.sh`, MSYS2 (5.2.37 / 5.3.9 close; 5.2 shown):

| Operation | Cost |
|---|---|
| `TArray.sort` n=100 | ~220 µs/elem, **22 ms total** |
| `TArray.sort` n=1000 | ~283 µs/elem, 283 ms |
| `TArray.sort` n=5000 | ~373 µs/elem, 1.9 s |
| mode delta at n=1000 | byte 294 · `-n` 372 · cmpFn 395 µs/elem |
| `TArray.binarySearch` on n=5000 | ~0.8–1.3 ms/search |
| `TArray.indexOf` full miss on n=5000 | ~290–480 ms/search (**~350× slower** than binarySearch) |
| `reverse` / `concat` | ~2–10 µs/elem |
| one `printf … \| sort` fork+pipe, n=1000 | ~45–57 ms total |

Read it honestly:

- **Below ~300–500 elements TArray.sort is FASTER than forking `sort`** (at
  n=100: 22 ms vs 45 ms — the fork+pipe dominates). This is the regime most
  scripts live in.
- **At thousands of elements `/usr/bin/sort` wins raw speed** (n=5000: ~50 ms
  vs our 1.9 s). Use it there — *if* your elements are newline-free and you
  don't need stability guarantees, a custom comparator, or an index back.
- What the external tool can never give you: **zero forks** (hot loops, PATH=''
  environments), **lossless arbitrary strings** (a `$'a\nb'` element corrupts
  line-based sort silently), **stable custom-comparator sorting**, and
  **binary search** over the result — plus the FPC-shaped API.

## FPC parity

FPC ships a dedicated fpcunit seed —
`packages/rtl-generics/tests/tests.generics.arrayhelper.pas` — and
[`tests/006_FpcParity.sh`](tests/006_FpcParity.sh) runs its cases verbatim
(fixture `(1 3 5 7 9 11 13 15 20)`): BinarySearch hit/miss/empty with exact
Candidate/Found/CompareResult values, IndexOf/First/Last, Min/Max with default,
Contains, Reverse (into-target AND in-place). All green. NB the seed has **no
Sort test** — sort parity rests on the sorted-invariant + hand matrices (and
the binarySearch loop is the FPC implementation transcribed line-for-line).

## Tests

`tests/001…007` — 80 cases, green on bash 5.2.37 **and** 5.3.9: wiring/contract,
sort modes/range/edges/rejects, stability + torture, binarySearch, scan family,
**FPC parity (006)**, copy/reverse/concat/compact. Rationale per case in
[`TEST_COVERAGE_NOTES.md`](TEST_COVERAGE_NOTES.md).
