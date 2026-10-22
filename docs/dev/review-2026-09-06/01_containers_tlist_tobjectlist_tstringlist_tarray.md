# Reviewer report G1 — tlist / tobjectlist / tstringlist / tarray (2026-09-06)

Repro scripts: `repro/g1/p1_tlist.sh … p6_53.sh` (paths inside may point at the original scratchpad; adjust `K=` to the kcl dir).

### Summary
All four suites are green on bash 5.2.37 (tlist 107/107, tobjectlist 31/31, tstringlist 160/160, tarray 80/80), and TArray is in good shape (sort/search/copy semantics match its pinned S1–S8, stability holds, lossless on hostile elements). The list hierarchy is weaker: (1) **no unit frees `${inst}_items`** — every TList/TObjectList/TStringList `.delete` leaks the array; (2) **TStringList.Add enforces `duplicates` and runs a full kklass-dispatched IndexOf on every Add even on unsorted/dupAccept lists** — 300 Adds take 15.5 s vs 0.1 s for TList (150×), and dupIgnore/dupError on unsorted lists contradicts FPC; plus `sorted = true` on a populated list silently leaves it unsorted so Find/Add give wrong answers; (3) **every index/count argument is fed unvalidated into `(( ))`** — a non-numeric index silently reads element 0 and `L.Get 'x[$(cmd)]'` executes `cmd` (TList, TObjectList, TArray range args). Two framework-level defects surfaced through these units (`$(obj.Get i)` returns "" for values `-e`/`-n`/`-E`; `.delete` fails under `set -u` for classes without a destructor).

### Findings

**G1-01 | HIGH | tlist/tobjectlist/tstringlist | kcl/tlist/tlist.sh:33-61 (no `destructor`), kcl/tobjectlist/tobjectlist.sh:103-115, kcl/tstringlist/tstringlist.sh:24-39 | `${inst}_items` is never freed on `.delete`**
kklass frees only `_data`/`_class`/wrappers; TList declares no destructor, TObjectList.Destroy frees the elements but not the array, TStringList inherits nothing. Every deleted list leaks a global array with its full contents (a `${inst}_items` of a later instance reusing the name is silently pre-populated until Create's `items_ref=()`).
Repro: `TList.new L; L.Add x; L.Add y; L.delete; declare -p L_items` → `declare -a L_items=([0]="x" [1]="y")` (same for TObjectList/TStringList, both bashes).
Fix: add `destructor Destroy` to TList doing `unset "${__inst__}_items"`; TObjectList.Destroy must end with `inherited`.

**G1-02 | HIGH | tlist/tobjectlist/tarray | tlist.sh:79,97,167,189,208,222,311,323,413,469,476; tobjectlist.sh:125,166,184-185,231; tarray.sh:141-145,268,270 | Index/count arguments go straight into `(( ))` — non-numeric input is code execution, and a bad index silently reads element 0**
Repro: `TList.new L; L.Add a; L.Get 'x[$(touch ~/pwn)]'` → file created, rc 0, RESULT=a. Same via `L.Delete '…'`, `L.capacity = '…'`, `TObjectList.Delete`, `TArray.sort a '…'`, `TArray.binarySearch a 1 0 '…'`. `L.Get abc` → RESULT=a (reads index 0). TArray.copy (line 408) already validates with a regex — the rest do not.
Fix: one `[[ "$index" =~ ^-?[0-9]+$ ]] || return 1` guard per entry (or a shared helper — decision D1: `kk.isInt`).

**G1-03 | HIGH | tstringlist | tstringlist.sh:217-232 | Duplicates policy is enforced on UNSORTED lists and costs an O(n) kklass-dispatched IndexOf per Add**
FPC (and the unit's own docs/TStringList.md:47 "Duplicates does nothing if the list is not sorted") apply Duplicates only when Sorted. Here `dupIgnore`/`dupError` drop items on unsorted lists, and even with dupAccept every Add walks the whole list calling `$this.CompareStrings` per element.
Repro: `L.duplicates = dupIgnore; L.Add a; L.Add a; L.count` → 1 (FPC 2). Perf: 300 Adds — TList 105 ms, TStringList **15,494 ms**. Sorted IndexOf is also linear (20 lookups on n=300: 1975 ms vs Find 124 ms).
Fix: skip the duplicate check unless `sorted == true`; when sorted, use the binary search (Find) for both the dup check and IndexOf (FPC: `IndexOf` = `Find` when Sorted); call `TStringList._cmpCore` directly instead of dispatching CompareStrings in loops.

**G1-04 | HIGH | tstringlist | tstringlist.sh:28,49 (`var sorted`, no setter) | `sorted = true` on a populated list does not sort → Find/Add wrong**
FPC `SetSorted(True)` sorts. Here `sorted` is a plain var, so the binary searches in Find (87-116) and Add (244-257) run on unsorted data.
Repro: `Add banana; Add apple; Add cherry; L.sorted = true; L.Find apple` → 1 (item at 1 is "apple" only by luck; list = banana|apple|cherry); `L.Add aardvark` → `aardvark|banana|apple|cherry`. docs/TStringList.md:79 promises auto-sort.
Fix: `property sorted read sorted write _setSorted` with `_setSorted` calling `$this.Sort` when turning true (mirrors the existing capacity/count pattern).

**G1-05 | HIGH | tstringlist | tstringlist.sh:224-226 | dupIgnore Add returns the CALLER's stale RESULT, not the existing index (trailer trap)**
`RESULT="$dup_index"; return` — an explicit `return` skips the func trailer, so `kk._invoke` restores the caller's RESULT (the very trap documented in tobjectlist.sh:210-213).
Repro (sorted, dupIgnore, list a b): `RESULT=SENTINEL; L.Add b; echo $RESULT` → `SENTINEL`; `$(L.Add b)` → `""`. Expected 1 (FPC returns existing index; test 007 only checks count, so it passes). Both bashes.
Fix: `kk._return "$dup_index"; return 0`.

**G1-06 | MED | tlist (+tstringlist inconsistency) | tlist.sh:160 | TList.Add returns the new COUNT, TStringList.Add returns the INDEX; FPC and docs/TList.md:109 say index**
Repro: `TList.new L; L.Add first; echo $RESULT` → 1 (FPC 0); `$(L.Add second)` → 2 (FPC 1). TStringList.Add (line 267) correctly returns insert_index. No test pins either value.
Fix: `RESULT="$current_count"` (kk._return) in TList.Add; add a test. (Decision R1.)

**G1-07 | MED | tobjectlist | tobjectlist.sh:57-69 (no override of `_setCount`/`_setCapacity`/`Assign`) | Owned elements leak on `count = N` shrink, `capacity < count`, and Assign frees everything then fails**
FPC `TList.SetCount` shrinks via `Delete` → Notify(lnDeleted) → freed; `SetCapacity < Count` raises EListError. Here (a) `L.count = 1` on an owning list of 2 leaves the dropped handle alive; (b) `L.capacity = 1` drops it alive; (c) inherited stub `TList.Assign` (tlist.sh:399) calls virtual `$this.Clear` → frees every owned element, then returns 1 "not implemented".
Repro: p2_tol.sh P2b/P2c/P2d: `o3: alive (FPC: freed)`, `o5: alive`, `Assign rc=1 o6: freed count=0`.
Fix: override `_setCount` (free `[new,count)` when owning), make `_setCapacity < count` an error (rc 1, no truncation — also fixes TList parity, see G1-09), and make TList.Assign fail BEFORE clearing.

**G1-08 | MED | tlist/tstringlist | tlist.sh:81,99,178,196,235,239,262,273,339,360,449,454,490,495; tstringlist.sh:61,200,259 | Loop counters `i`/`j` are globals — they clobber the caller's variables**
Repro: `i=777; L.IndexOf c; echo $i` → 2; `L.Insert 0 z` → 0; TStringList `j=6; L.Add c` (sorted) → j=2.
Fix: `local i j` at the top of each body.

**G1-09 | MED | tlist | tlist.sh:74-89 | `capacity` setter accepts negatives and values < count: silent truncation / corrupt state**
`L.capacity = -3` on a 2-item list → kklass prints `unset: [-3]: bad array subscript`, then count=-3, capacity=-3, items gone. `L.capacity = 2` on 5 items → silently drops 3 (FPC raises EListError SListCapacityError).
Repro: p1_tlist.sh P1f/P1g. Fix: reject `new_capacity < count` and `< 0` with rc 1, unchanged. (Decision R2.)

**G1-10 | MED | tstringlist | tstringlist.sh:118-140 | Assign copies items only: dst flags untouched, a `sorted` dst receives unsorted data**
Repro: src `b a`; dst `sorted=true`; `D.Assign S` → items `b|a`, `D.Find a` → -1 (miss). FPC/Delphi TStringList.Assign also copies CaseSensitive/Duplicates/Sorted from a TStringList source (FPC stringl.inc `TStringList.Assign` — verify against the FPC source); at minimum a sorted destination must re-sort or clear `sorted`.
Fix: after the copy, copy the three flags from a TStringList source (or `sorted=false`).

**G1-11 | MED | tstringlist | tstringlist.sh:120,147 | Assign and AddStrings fork (`$($source.count)`)**
Instrumented `S.count` shows BASHPIDs ≠ parent — one fork per call. Also with a nonexistent source AddStrings prints a kklass "command not found" and returns 0 (line 147-150).
Fix: read `${source}_data[count]` via nameref; validate `declare -F "$source.count"` first.

**G1-12 | MED | tarray | tarray.sh:136-137, 224-231 (and 333-334) | An undefined comparator name is silently treated as the START index → byte-order sort/search, wrong result**
`declare -F "$1"` fails for a typo'd name, so it falls through to the range parser and evaluates to 0.
Repro: `a=(10 9 100); TArray.sort a myUndefinedCmp` → rc 0, `10 100 9`; `TArray.binarySearch a 3 noSuchFn` → rc 0 RESULT=1 (start="noSuchFn"). Conversely `TArray.min a f` with default `f` that happens to be a function → default eaten, RESULT="".
Fix: if arg is non-numeric and not `-n` and not a function → rc 2 (argument error); treat only `^-?[0-9]+$` as start/count.

**G1-13 | MED | kklass (seen via all units) | kbool/kklass/kklass.sh:98 | `kk._return` uses `echo -n "$value"` — values `-e`, `-n`, `-E`, `-en`… are lost under `$( )`**
Repro: `L.Add -e; c=$(L.Get 0); echo "[$c]"` → `[]` (direct call RESULT is fine). Both bashes. Affects every func/computed property in kcl. Fix: `printf '%s' "$return_value"`.

**G1-14 | LOW | kklass (seen via tlist) | kklass.sh:536 | `.delete` fails under `set -u` for any class without a destructor**
`( set -u; TList.new U; U.delete )` → `!__kk_dv: unbound variable` on 5.2 and 5.3. Fix: `${!__kk_dv:-}`.

**G1-15 | LOW | tarray | tarray.sh:267-268 | binarySearch range is not clamped to the array**
`a=(1 3 5 7); TArray.binarySearch a 9 2 10` → rc 1, CANDIDATE=11, COMPARE=-1 (compared against nonexistent elements). sort clamps (line 144); binarySearch should too.

**G1-16 | LOW | tobjectlist | tobjectlist.sh:91-100, 108/123/…, 229-231 | Loose boolean tokens**
`L.owns_objects = "yes"` → silently non-owning (anything ≠ `true`); `FindInstanceOf TList no` → treated as exact=true; `startAt=abc` → 0 (and G1-02). Fix: validate `true|false` on write (a property setter) and reject other tokens rc 2.

**G1-17 | LOW | tstringlist | tests/015_KklassResultCompatibility.sh:46-63 | Test that cannot fail**
It greps `tstringlist.sh` for `method Assign '{` (the pre-Pascal-DSL syntax); the pattern no longer exists (grep count 0), so `assign_block` is empty and the "avoids eval" assertion always passes.

**G1-18 | LOW | tlist | tlist.sh:246-252 | Clear does O(n) `unset` per element via `_setCount 0`, then `items_ref=()`** — harmless double work; set `count`/`capacity` raw and just reassign the array.

**G1-19 | LOW | tstringlist | docs/TStringList.md | Docs are a verbatim Delphi DocWiki dump**
They document Names/Values/NameValueSeparator/Text/CommaText/DelimitedText/Delimiter/QuoteChar/AddObject/Objects/OwnsObjects/LoadFromFile/CustomSort/SetSorted/Assign-flags — none exist in tstringlist.sh (the unit is Add/Insert/IndexOf/Find/Sort/Remove/Assign/AddStrings/CompareStrings only). No README/TEST_COVERAGE_NOTES exists for tlist/tstringlist to state what IS ported. Same for docs/TList.md (Extract/ExtractItem/GetEnumerator/Notify documented, absent).

### Test gaps
- No test that `${inst}_items` is gone after `.delete` (any of the three classes); no `set -u` run.
- No test of TList.Add's return value; TStringList dupIgnore tests check count only, never the returned index (G1-05 hidden).
- No test of Duplicates on an UNSORTED list, nor of `sorted = true` on a populated list, nor Assign into a sorted/case-insensitive destination.
- No non-numeric / injection-shaped index tests anywhere (only "very large" and negative integers).
- No caller-variable-isolation test (`i`, `j`, `RESULT` preservation on success paths).
- TObjectList: no `count =` / `capacity =` shrink test, no Assign test, no `owns_objects = garbage` test, no element-destructor re-entrancy test.
- TArray: no test for an undefined comparator name, no binarySearch out-of-range `start/count`, no `min/max` default-that-is-a-function.
- TStringList perf: 016 sorts 50 items; nothing exercises Add at n≥300 (would have exposed the 15 s wall).
- tstringlist 010 "Invalid capacity assignment" passes unconditionally (`kt_test_pass` regardless of result).
- Nothing covers `$()` capture of values beginning with `-e`/`-n`.

### Reviewer's questions (resolved by owner decisions D1, R1, R2; TStringList missing surface → P2 docs trim + roadmap; sorted IndexOf = Find)
