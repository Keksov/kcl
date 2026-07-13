# TArray — upstream FPC API reference

Source of truth: FPC rtl-generics `generics.collections.pas` —
`TCustomArrayHelper<T>` (:73–102, incl. `TBinarySearchResult` :68–71) and
`TArrayHelper<T>` (:106–138); implementation: introsort `QSort`/`Median`/
`HeapSort` (~:990–1220), `BinarySearch` (:1225–1310), `Copy`/`Reverse`/`Concat`/
scan family (:1296–1457). Delphi `System.Generics.Collections.TArray` is the
same API household. The parity oracle is FPC's own fpcunit seed
`packages/rtl-generics/tests/tests.generics.arrayhelper.pas`, mined verbatim
into `tests/006_FpcParity.sh`.

Upstream declaration shape (abridged):

```pascal
TBinarySearchResult = record
  FoundIndex, CandidateIndex: SizeInt;
  CompareResult: SizeInt;
end;

TCustomArrayHelper<T> = class abstract
  class procedure Sort(var AValues: array of T); overload;
  class procedure Sort(var AValues: array of T; const AComparer: IComparer<T>;
    AIndex, ACount: SizeInt); overload;
  class function BinarySearch(const AValues: array of T; const AItem: T;
    out ASearchResult: TBinarySearchResult; ...): Boolean; overload;
  class function BinarySearch(const AValues: array of T; const AItem: T;
    out AFoundIndex: SizeInt; ...): Boolean; overload;
end;

TArrayHelper<T> = class(TCustomArrayHelper<T>)
  class function  Concat(const Args: array of TArray<T>): TArray<T>;
  class function  IndexOf / FirstIndexOf / LastIndexOf(...): SizeInt;
  class function  Contains(...): Boolean;
  class function  Min / Max(...; aDefault: T): T;
  class procedure Copy(const aSource; var aDestination; [aSourceIndex,
                       aDestIndex,] aCount);
  class procedure Reverse(const aSource: TArray<T>; var aTarget: TArray<T>);
end;
```

## kcl mapping conventions

- **Static class over caller-named arrays.** FPC's class functions take the
  array as a parameter; here you pass the **array name** and the method uses a
  nameref. Data stays yours; TArray holds no state.
- **Both `BinarySearch` overloads in one call**: `RESULT` = the `AFoundIndex`
  overload, `RESULT_CANDIDATE`/`RESULT_COMPARE` = the `TBinarySearchResult`
  overload, flattened per the kcl RESULT-globals convention.
- **`IComparer<T>` → a comparator argument**: nothing (byte order) · `-n`
  (int64) · a plain function name (`cmpFn a b`, exit code 0 = `<`, 1 = `=`,
  2 = `>`). No interface objects — a kklass dispatch per comparison inside an
  n·log n loop would be ruinous; a plain function is the bash analogue of a
  code pointer.
- **Indices are 0-based on both sides** (FPC dynamic arrays) — values map with
  no adjustment (unlike tregex, where Delphi `TMatch.Index` is 1-based).
- rc: 0 ok/found/true · 1 not-found/false/rejected · 2 argument error.

---

## Members

### Sort
```pascal
class procedure Sort(var AValues: array of T); overload;
class procedure Sort(...; const AComparer; AIndex, ACount: SizeInt); overload;
```
→ **`TArray.sort arr [cmp|-n] [start count]`**, in place. Range =
`[AIndex .. AIndex+ACount−1]`, `ACount<=1` → no-op (impl :1059–1065, S8).

**Algorithm delta (documented improvement):** FPC uses introsort
(quicksort + heapsort fallback; order of EQUAL elements *unspecified*). This
port uses a bottom-up iterative **stable** mergesort: same O(n log n) worst
case, no recursion, and equal elements keep input order — every FPC-legal
output is reproduced or refined, never contradicted. The FPC fpcunit seed has
no Sort test; sort correctness is pinned by the sorted-invariant + matrices.

### BinarySearch
```pascal
class function BinarySearch(const AValues; const AItem;
  out ASearchResult: TBinarySearchResult; ...): Boolean;
```
→ **`TArray.binarySearch arr item [cmp] [start count]`** — the FPC loop
(:1243–1292) transcribed line-for-line: compares `Compare(AValues[mid], AItem)`
(array element FIRST), `<0` → right half, `>=0` → left half, `=0` → found.
- hit: `RESULT`=`RESULT_CANDIDATE`=index, `RESULT_COMPARE`=0, rc 0.
- miss: `RESULT`=−1, `RESULT_CANDIDATE`= convergence index (the insertion
  point), `RESULT_COMPARE`=`sign(array[candidate] − item)`, rc 1.
- empty (S1, :1231–1237): −1 / −1 / 0, rc 1.
Precondition as in FPC: the array is sorted under the SAME comparator
(garbage-in-garbage-out).

### IndexOf / FirstIndexOf / LastIndexOf / Contains
```pascal
class function IndexOf(...): SizeInt;   // = FirstIndexOf (impl :1371)
```
→ **`TArray.indexOf|firstIndexOf|lastIndexOf arr item [cmp]`** — linear scans;
`indexOf` delegates to `firstIndexOf` exactly like the FPC source. `Contains`
(:1342) = `IndexOf <> -1` → **`TArray.contains`**, rc only.

### Min / Max
```pascal
class function Min(const Args; const AComparer; const aDefault: T): T;
```
→ **`TArray.min|max arr [cmp] [default]`** — returns the **value** (not the
index); empty array → `default` with rc 1 (FPC test: `[]` → −1 default).
Strictly-less/greater replace ⇒ ties keep the first occurrence.

### Copy
```pascal
class procedure Copy(const aSource; var aDestination; aCount); overload;
class procedure Copy(...; aSourceIndex, aDestIndex, aCount); overload;
```
→ **`TArray.copy src dst count`** / **`TArray.copy src dst srcIdx dstIdx count`**.
FPC-strict (S6, impl :1301–1322): same array → error (`SErrSameArrays` → rc 2);
`count<0` or beyond `len(src)−srcIdx` / `len(dst)−dstIdx` → error; the
destination is **not** auto-grown — pre-size it. (Resolved deliberately
FPC-faithful: silent growth would mask bugs and create partial arrays.)

### Reverse
```pascal
class procedure Reverse(const aSource: TArray<T>; var aTarget: TArray<T>);
```
→ **`TArray.reverse src dst`** — builds through a temp buffer (impl :1324–1339
does exactly this "in case aSource=aTarget"), so `reverse a a` is safe;
distinct source is left untouched. FPC test covers both forms.
**`TArray.reverseInPlace arr`** is a bash convenience wrapper.

### Concat
```pascal
class function Concat(const Args: array of TArray<T>): TArray<T>;
```
→ **`TArray.concat dst src1 [src2 …]`** — varargs of array **names**; empty
sources contribute nothing (S7, the `CurLen>0` guard :1347–1369); built in a
temp so `dst` may itself be a source.

### compact (bash extra — no FPC counterpart)
**`TArray.compact arr`** re-indexes a sparse bash array to dense `0..n−1`.
Needed because bash arrays can have holes while FPC dynamic arrays cannot; the
dense contract of every other member assumes FPC shape. This is the ONE place
holes are dropped.

## Not ported (wontfix)

| Upstream | Reason |
|---|---|
| `IComparer<T>` objects, `TComparerBugHack`, interface machinery | comparator = plain function / mode flag; no object protocol in bash worth its dispatch cost |
| Introsort internals (`QSort`, `Median`, `HeapSort`, `reasonable` depth) | the ALGORITHM is not the contract, the sorted result is; stable mergesort chosen (see Sort) |
| Pointer forms (`PT`, slices, open-array views) | no pointers in bash |
| Generic element types | elements are bash strings; `-n` covers int64; floats route through kcl/math comparators as a cmpFn if ever needed |
| NUL bytes in elements | bash language limit |
