# tarray — test coverage notes

**Status: FINALIZED at P4 (2026-07-13).** Suite 001–007 = 80 cases, green on
bash 5.2.37 AND true 5.3.9. P4 added README.md, docs/TArray.md, and bench.sh —
`bench.sh` is a benchmark (its numbers live in README.md/the ledger), not a
test, so it adds no rows here.

Protocol (same as dateutils/math/tdictionary/tstopwatch/tregex): every
**invented** test case gets a row here; the **FPC-traceable** cases
(006_FpcParity.sh, mined from `packages/rtl-generics/tests/tests.generics.arrayhelper.pas`)
cite their FPC procedure instead. **Sort has NO FPC seed** (the arrayhelper
fpcunit has no Sort test), so ALL of 002/003 are invented — basis = the
sorted-invariant, hand matrices, and the stability definition. The seed's
indices are 0-based (Delphi dynamic array), so binarySearch/indexOf map with
NO adjustment (unlike tregex's 1-based `TMatch.Index`). Classes:
`contract` (dispatch/RESULT/rc/zero-fork), `behavior` (documented semantics),
`improvement` (a bash-side guarantee stronger than FPC), `torture` (hostile
elements).

## 001 — skeleton (wiring + contract)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 001.defined | all 13 | every declared member defined after `build` | contract | kklass build |
| 001.pending-stubs | 12 (search/min/max/copy/…) | pending members dispatch, return `__tarray_stub__:X` | contract | phase discipline (real bodies P2/P3) |
| 001.direct-silent | min (stub) | direct call sets RESULT, prints nothing | contract | static-proc contract (P0) |
| 001.no-leak | binarySearch (stub) | `$()` subshell does not leak globals | contract | call-direct rule |
| 001.result-shape | binarySearch (stub) | RESULT_CANDIDATE/RESULT_COMPARE present | contract | TBinarySearchResult flattening |
| 001.zero-fork | sort | source + real sort under `PATH=''` | contract | builtins only |

## 002 — sort: modes, range, edges, rejects

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 002.byte-order | sort | default = BYTE order (upper<lower, digit<upper<lower) | behavior | LC_ALL=C strcmp (P0 idiom); locale-collation is a non-goal |
| 002.numeric | sort -n | negatives / zero / leading zeros; original strings preserved (007≠7) | behavior | 10#-normalized key; lossless elements |
| 002.numeric-64bit | sort -n | ±2^62 sort correctly | behavior | bash 64-bit `(( ))` |
| 002.cmpFn | sort fn | by-length and reverse-numeric comparators (rc 0/1/2) | behavior | §2.4 comparator protocol |
| 002.range | sort … start count | only [start,count) sorted; outside untouched; count≤1 no-op; count clamped | behavior | S8 (impl :1059-1065) |
| 002.edges | sort | empty/single/all-equal/already-sorted/reversed | behavior | sorted-invariant boundaries |
| 002.reject-assoc | sort | associative array → rc 1 | behavior | §2.2 (no order to sort) |
| 002.reject-nonint | sort -n | non-integer element → rc 1, array unchanged | behavior | §2.3 (no silent lexicographic fallback) |
| 002.reject-noname | sort | missing array name → rc 2 | contract | argument error |

## 003 — sort: stability, torture, zero-fork

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.stable-firstchar | sort fn | equal first-char keeps INPUT order | improvement | STABLE (FPC introsort equal-order unspecified) |
| 003.stable-tagged | sort fn | equal `value:seq` keeps seq order | improvement | stability definition |
| 003.stable-dups | sort | many-duplicate default sort, equal order kept | improvement | stability |
| 003.torture-exotic | sort | newline/glob/space/empty elements, lossless byte-order | torture | array-write lossless; `[[ < ]]` |
| 003.torture-shell | sort | quotes/backticks/`$()`-looking/unicode — no expansion | torture | quoting discipline |
| 003.sentinel-data | sort | an element equal to a stub sentinel is just data | torture | no magic strings |
| 003.correctness-200 | sort -n | 200 pseudo-random ints end up non-decreasing | behavior | sorted-invariant |
| 003.zero-fork | sort | all 3 modes complete under `PATH=''` | contract | builtins only |

## 004 — binarySearch

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.hit | binarySearch | RESULT=index, candidate=index, compare 0, rc 0 | behavior | FPC impl :1258-1262 |
| 004.miss-below | binarySearch | candidate=insertion (0), compare>0, found -1, rc 1 | behavior | S2 (array[cand]>item) |
| 004.miss-above | binarySearch | candidate=last, compare<0, found -1 | behavior | S2 (array[cand]<item) |
| 004.empty | binarySearch | found -1, candidate -1, compare 0, rc 1 | behavior | S1 (impl :1231-1237) |
| 004.single | binarySearch | 1-element hit@0 / miss -1 | behavior | boundary |
| 004.modes | binarySearch | byte-order + cmpFn (by length) search | behavior | comparator protocol |
| 004.range | binarySearch | search restricted to [start,count) | behavior | range form |
| 004.closure | sort+binarySearch | sort then every element findable at a correct index | cross-check | sort∘search closure |
| 004.torture | binarySearch | element with newline, byte-order | torture | lossless |
| 004.no-name | binarySearch | missing array name → rc 2 | contract | argument error |

## 005 — scan family (indexOf / first / last / contains / min / max)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 005.indexof-first | indexOf/firstIndexOf | equal, both = first occurrence | behavior | S3 (impl :1371) |
| 005.lastindexof | lastIndexOf | last occurrence | behavior | reverse scan |
| 005.miss | indexOf | -1, rc 1 | behavior | linear-scan oracle |
| 005.single-occ | first/last | single occurrence → first==last | behavior | boundary |
| 005.contains | contains | present/absent/empty → rc 0/1/1 | behavior | impl :1342 (IndexOf<>-1) |
| 005.minmax-value | min/max | numeric min/max value | behavior | S5 |
| 005.minmax-empty | min/max | empty → default, rc 1 | behavior | S5 (aDefault) |
| 005.minmax-strings | min/max | original strings preserved (007≠7) | behavior | lossless |
| 005.minmax-single | min/max | single element | behavior | boundary |
| 005.min-tie-first | min | equal-key tie → first occurrence | behavior | strictly-less replace |
| 005.modes | min/max/indexOf | byte-order + cmpFn (by length) | behavior | comparator protocol |
| 005.torture | indexOf | newline / unicode elements | torture | lossless |
| 005.zero-fork | scan family | all complete under `PATH=''` | contract | builtins only |

## 006 — FPC parity (FPC-TRACEABLE; tests.generics.arrayhelper.pas)

Verbatim FPC fixtures/expected values (integer `-n` mode = `TComparer<Integer>.Default`);
0-based, no index adjustment. Basis column = the FPC procedure.

| ID | Members | Case | Basis (FPC proc) |
|---|---|---|---|
| 006.binsearch | binarySearch | 10→false/cand5/found-1/cmp>0; 20→true/cand8/found8/cmp0 | Test_BinarySearch_Integers |
| 006.binsearch-empty | binarySearch | empty→false/cand-1/found-1/cmp0 | Test_BinarySearch_EmptyArray |
| 006.indexof | indexOf | 9→4, 33→-1 | Test_IndexOf |
| 006.first-last | first/lastIndexOf | 9→4 first / 7 last in (…,9,11,13,9,20) | Test_FirstIndexOf/Test_LastIndexOf |
| 006.min-max | min/max | 1 / 20 ; empty → default -1 | Test_Min / Test_Max |
| 006.contains | contains | 15 true, 14 false, empty false | Test_Contains |
| 006.reverse | reverse | reverse(a,b) = reversed; reverse(a,a) in-place, source-safe | Test_Reverse |

## 007 — copy / reverse / concat / compact

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 007.reverse | reverse | into target, source untouched | behavior | S4 (impl :1324-1339) |
| 007.reverse-inplace | reverse | src==dst safe via temp | behavior | S4 (the "in case aSource=aTarget" temp) |
| 007.reverse-edges | reverse/reverseInPlace | empty / single / rc 2 no-name | behavior | boundary |
| 007.copy-count | copy | count form src[0..]→dst[0..] | behavior | impl :1296-1298 |
| 007.copy-indexed | copy | srcIdx/dstIdx/count form | behavior | impl :1301 |
| 007.copy-same | copy | same array → rc 2 (SErrSameArrays) | behavior | S6 (impl :1307) |
| 007.copy-bounds | copy | dst-too-small (not grown) / count>src / negative → rc 2 | behavior | S6 (impl :1309-1312) STRICT |
| 007.copy-zero | copy | count 0 → no-op | behavior | boundary |
| 007.concat | concat | src1++src2++src3 | behavior | S7 (impl :1347-1369) |
| 007.concat-empty | concat | empty sources skipped; all-empty → empty | behavior | S7 (CurLen>0 guard) |
| 007.concat-self | concat | dst may be a source (temp-built) | behavior | bash-safe extension |
| 007.compact | compact | sparse → dense, order kept | behavior | bash extra (§2.1) |
| 007.torture | reverse/concat | newline/glob/quotes elements lossless | torture | array-write lossless |
| 007.zero-fork | copy/reverse/concat/compact | complete under `PATH=''` | contract | builtins only |
