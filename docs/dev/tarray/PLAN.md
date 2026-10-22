# TArray (Sort / BinarySearch / helpers) → bash port plan (kcl/tarray)

**Roadmap position:** 3/7 (owner priority order, 2026-07-12).
**Source of truth:** FPC rtl-generics `generics.collections.pas` — `TCustomArrayHelper<T>` (:73–102, incl. `TBinarySearchResult` :68–71) + `TArrayHelper<T>` (:106–138). Implementation: introsort `QSort`/`Median`/`HeapSort` (~:990–1220), `BinarySearch` (:1225–1310 TBinarySearchResult overload; :1457–1520 FoundIndex overload). Delphi `TArray` is the same API household.
**Target:** `kcl/tarray/tarray.sh` — kklass Pascal-DSL **static** class `TArray` operating on caller arrays **by name** (nameref), model tpath/dateutils/math.
**Ledger:** `kcl/tarray/tarray_ledger.json`.
**Workflow:** phase → dual-bash tests → full master sweep → STOP → "go"; commits gated; no unit edits during a sweep.
**Conventions:** as `kcl/tdictionary/PLAN.md` §2.2–2.4/§6.

---

## 1. Scoping analysis

Everything is Tier A (pure bash, zero forks). The selling point vs the external `sort`
binary is NOT raw speed — it is **correctness for arbitrary strings + zero forks**:
`sort` is line-based (breaks on elements containing newlines), costs a fork+pipe per
call, and cannot binary-search. `TArray.sort` is lossless for any bash string and fork-free;
its niche is the small-to-mid arrays (n ≤ ~5k) that dominate script reality. bench.sh
publishes honest per-element costs; README states the positioning.

### Ported

| FPC | bash | Notes |
|---|---|---|
| `Sort(var AValues)` | `TArray.sort arr` | default byte-order string compare (§2.3) |
| `Sort(var AValues; AComparer)` | `TArray.sort arr cmpFn` / `TArray.sort arr -n` | `-n` = numeric mode (int64); cmpFn = plain bash function (§2.4) |
| `Sort(...; AIndex, ACount)` | `TArray.sort arr [cmp] start count` | range form |
| `BinarySearch(...; out AFoundIndex)` | `TArray.binarySearch arr item [cmp]` | rc 0/1; RESULT=FoundIndex (miss → -1) |
| `BinarySearch(...; out TBinarySearchResult)` | same call, extra outputs | RESULT_CANDIDATE, RESULT_COMPARE (record :68–71) |
| `IndexOf` / `FirstIndexOf` / `LastIndexOf` (:124–129) | `TArray.indexOf arr item [cmp]` … | linear scans; IndexOf≡First pin at P0 from impl |
| `Contains` (:137) | `TArray.contains arr item [cmp]` | rc |
| `Min` / `Max` (…; aDefault) (:130–133) | `TArray.min arr [cmp] [default]` | empty → default (FPC signature has aDefault) |
| `Copy` (count / src,dst,idx,count) (:134–135) | `TArray.copy src dst count` + indexed form | bounds semantics pinned at P0 |
| `Reverse(aSource, aTarget)` (:136) | `TArray.reverse src dst` | FPC copies REVERSED INTO TARGET (not in-place) — pinned |
| `Concat(Args)` (:123) | `TArray.concat dst src1 [src2 …]` | varargs of array NAMES |

Bash-convenience extras (TEST_COVERAGE_NOTES rows): `TArray.reverseInPlace arr`,
`TArray.compact arr` (re-index sparse → dense; see §2.2), `TArray.shuffle` NOT included
(random lives in kcl/math randomRange — a composition example goes in README instead).

### NOT ported (wontfix)

1. **IComparer<T> objects / TComparerBugHack / interface machinery** — comparator is a
   plain bash function name (or a mode flag); no object protocol.
2. **Introsort internals** (`QSort`/`Median`/`HeapSort`, `reasonable` depth budget) — the
   ALGORITHM is not the contract; the sorted RESULT is (§2.5).
3. **Pointer forms** (`PT`, `Slice`, open-array views) — no pointers in bash.
4. **Generic element types** — elements are bash strings; numeric mode covers int64;
   floats route through kcl/math comparators if ever needed (README example), NOT here.
5. **NUL bytes** in elements (bash limit).

---

## 2. Design decisions

### 2.1 Arrays by name, dense expectation
Methods take the caller's INDEXED array name and access via `declare -n` with `__ta_`
local prefix (collision rule documented: don't pass `__ta_*` names). Contract: indices
**dense 0..n-1** — the FPC data model. Sparse input is NOT silently compacted (silent
re-indexing would surprise callers); `TArray.compact arr` is the explicit tool, and
sort/search on sparse arrays are documented as undefined (a cheap density check runs
only under VERBOSE_KKLASS=debug — hot paths stay lean).

### 2.2 Assoc arrays rejected
`${arr@a}` must contain no `A` — assoc arrays have no order to sort; rc=1 (pinned test).

### 2.3 Default comparators — determinism first
- **String mode (default):** byte order via `LC_ALL=C` scoped comparison
  (`[[ < ]]` under the C locale = strcmp). Locale-collation sorting is a documented
  NON-goal (non-deterministic across machines — the enemy of tests).
- **Numeric mode (`-n`):** 64-bit integer compare via `(( ))`; elements failing an
  integer-shape check → rc=1 (no silent lexicographic fallback — that's how GNU sort
  bugs are born). Shape regex pinned at P0 (`^-?[0-9]+$`, leading zeros allowed via 10# guard).

### 2.4 Custom comparator protocol — fork-free by construction
`cmpFn a b` is a PLAIN bash function (kklass dispatch at ~0.5 ms/call × n·log n calls
would be catastrophic). Result via **return code**: `0` = a<b, `1` = a==b, `2` = a>b
(no stdout — echo would need `$()` = fork per comparison). The two built-in modes are
INLINED in the merge loop (zero function-call overhead); cmpFn path calls the function
directly. Contract + a worked example in README.

### 2.5 Algorithm: bottom-up iterative MERGESORT (stability documented)
FPC uses introsort (unstable, recursion + heap fallback). Bash pick: **bottom-up
mergesort** — no recursion (bash stack depth + function-call cost), guaranteed
O(n log n) worst case (introsort's own goal), simple inlined compares, and STABLE.
Parity note: FPC's order among equal elements is UNSPECIFIED, so any order is
parity-compatible; stability is a strictly stronger, documented guarantee (bash-side
improvement row in TEST_COVERAGE_NOTES). O(n) scratch array is fine at target sizes.

### 2.6 BinarySearch — both FPC result shapes in one call
`TArray.binarySearch arr item [cmp] [start count]` → rc 0 found / 1 not found;
`RESULT` = FoundIndex (-1 on miss), `RESULT_CANDIDATE` = CandidateIndex,
`RESULT_COMPARE` = last CompareResult sign — the TBinarySearchResult record (:68–71)
flattened to the RESULT_* convention. Empty array: FoundIndex=-1, CandidateIndex=-1,
CompareResult=0, rc=1 (:1231–1237 verbatim). Found-index tie behavior (which duplicate
is reported) and miss-side CandidateIndex semantics pinned at P0 from :1225–1310 —
the loop converges leftmost-candidate; the exact contract (insertion point vs nearest)
is recorded as read, and tests fix it byte-for-byte. Precondition: array sorted under
the SAME comparator (garbage-in-garbage-out, like FPC; documented).

## 3. Pinned semantics (verify/finalize at P0)

| # | Semantic | Source | Status |
|---|---|---|---|
| S1 | BinarySearch empty → (-1,-1,0,false) | :1231–1237 | pinned from source |
| S2 | BinarySearch duplicate-tie index + miss CandidateIndex contract | :1225–1310 | read fully at P0 |
| S3 | IndexOf vs FirstIndexOf equivalence | impl of :124–127 | pin at P0 |
| S4 | Reverse copies INTO target; source untouched; dst re-created | :136 impl | pin at P0 |
| S5 | Min/Max return aDefault on empty; tie → first occurrence? | :130–133 impl | pin at P0 |
| S6 | Copy bounds/overlap behavior (src==dst?) | :134–135 impl | pin at P0 |
| S7 | Concat with empty sources / empty result | :123 impl | pin at P0 |
| S8 | Sort range form: outside [start,count) untouched | :85–86 | pinned |

## 4. Parity & test model

Seeds: **an FPC array-helper fpcunit file WAS found at P0** —
`packages/rtl-generics/tests/tests.generics.arrayhelper.pas` (BinarySearch/IndexOf/
First/Last/Min/Max/Contains/Reverse, fixture `(1 3 5 7 9 11 13 15 20)`) — mined into
`tests/00X_FpcParity.sh` as the parity oracle. It has NO Sort test, so sort parity =
the sorted-invariant + hand matrices. Basis: that seed + implementation-source reading
(line refs above, for the BinarySearch sign/candidate and Copy/Reverse/Concat detail) + hand
matrices: sorted/reverse/random/all-equal/single/empty arrays; duplicates (stability
proof for cmpFn mode with tagged elements); exotic elements ('', newline, glob, unicode,
`-n` negatives/zeros/±2^62); range forms; binarySearch hit/miss/first/last/candidate
matrix vs a linear-scan oracle; cross-check sort+binarySearch closure (every element
findable); zero-fork PATH=''; dual-bash. Non-FPC cases → TEST_COVERAGE_NOTES rows.

## 5. Phases

- **P0 — semantics pin + design freeze + skeleton.** Read impl for S2–S7; record answers
  here; freeze comparator protocol + LC_ALL=C idiom + density contract; skeleton +
  runner; baseline re-measure. STOP.
- **P1 — sort.** Bottom-up merge core; string/numeric/cmpFn modes; range form; stability
  proof tests; torture matrix. Sweep gate. STOP.
- **P2 — binarySearch + scan family.** binarySearch (both shapes, oracle cross-checks),
  indexOf/firstIndexOf/lastIndexOf/contains, min/max. Sweep gate. STOP.
- **P3 — copy / reverse / concat + compact extra.** S4/S6/S7 semantics. Sweep gate. STOP.
- **P4 — docs, bench, closeout.** README (positioning vs `sort`, comparator contract,
  worked examples), docs/TArray.md (upstream reference per kcl docs convention), bench.sh
  (per-element cost at n=100/1k/5k, default vs cmpFn, binarySearch cost, vs `sort` fork
  informational), TEST_COVERAGE_NOTES finalized, ledger COMPLETE, final sweep. STOP.

## 6. Bash traps to respect

1. `__ta_` prefix on ALL locals in nameref methods; reject `__ta_*` as caller names.
2. `[[ < ]]` collates by locale — byte order ONLY under scoped `LC_ALL=C`; pin the
   scoping idiom at P0 (var-assignment prefix does not affect builtins uniformly across
   the two bashes — probe!).
3. Comparator rc protocol: `(( rc == 2 ))` etc.; NEVER `$()` in the compare hot path.
4. Numeric compare needs `10#` guards (leading zeros → octal trap).
5. `arr=("${arr[@]}")` compacts (drops holes) — that's `compact`'s job, nowhere else.
6. Merge scratch arrays are locals — `local -a __ta_buf` (no globals leaked).
7. `kk._return ""` on func fail paths (kklass trailer trap).
8. Elements with trailing newlines: lossless only via array writes (never `$()` pipelines).

## 7. Deliverables

`kcl/tarray/`: tarray.sh, PLAN.md, tarray_ledger.json, README.md, docs/TArray.md,
bench.sh, TEST_COVERAGE_NOTES.md, tests/001…+tests.sh.
