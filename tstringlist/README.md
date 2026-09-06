# kcl/tstringlist — TStringList for bash

A bash port of Free Pascal's `Classes.TStringList` as a kklass **instantiable**
class deriving from [`TList`](../tlist/README.md): a string list with optional
**sorting**, a **duplicates policy** and **case-insensitive** comparison.

```bash
source kcl/tstringlist/tstringlist.sh

TStringList.new l
l.Add banana; l.Add apple; l.Add cherry
l.sorted = true                 # sorts NOW (FPC SetSorted), and keeps order
l.Add aardvark                  # RESULT=0 — inserted in order
l.Find apple                    # RESULT=1 (hit) / -(insertion point)-1 (miss)
l.IndexOf apple                 # RESULT=1 — binary search while sorted

l.duplicates = dupIgnore        # only bites while sorted (FPC)
l.Add apple                     # RESULT=1, count unchanged

l.case_sensitive = false        # default: fold both sides before comparing
l.delete
```

Everything `TList` offers (`Get`/`Put`/`Delete`/`Clear`/`count`/`capacity`/
`Exchange`/`Move`/`Pack`/`First`/`Last`/`CustomSort`/`BatchInsert`/
`BatchDelete`) is inherited unchanged.

## Contract

Same [kcl contract](../README.md#1-the-kcl-contract) as `TList`: values in
`RESULT` (a direct call is silent), errors are rc 1 with no output and no
partial state, indices validated before arithmetic, `set -eu` clean, no forks,
and `l.delete` frees `${l}_items`.

## API — what this class adds

| Member | Result | Notes |
|---|---|---|
| `l.case_sensitive` / `= true\|false` | flag | default `false`: both sides are lower-cased before comparing |
| `l.sorted` / `= true\|false` | flag | **the setter sorts** when it flips to true (FPC `SetSorted`); any other token is rc 2 |
| `l.duplicates` / `= dupAccept\|dupIgnore\|dupError` | policy | default `dupAccept`; **applies only while `sorted` is true** (FPC) |
| `l.Add s` | **index** of the element | sorted: inserted in order; `dupIgnore` on a hit returns the **existing** index without adding; `dupError` on a hit is rc 1 |
| `l.Insert i s` | — | rc 1 on a sorted list (FPC: the position is not yours to choose) |
| `l.IndexOf s` | index or `-1` | binary search while sorted, linear otherwise (FPC) |
| `l.Find s` | index, or `-insertionPoint - 1` | **sorted lists only**, else rc 1 |
| `l.Sort` | — | stable case-fold sort via [`TArray.sort`](../tarray/README.md); sets `sorted` |
| `l.Remove s` | removed index, or `-1` | uses the same comparison as `IndexOf` |
| `l.CompareStrings a b` | `0` equal, `1` a<b, `2` a>b | honours `case_sensitive` |
| `l.Assign src` | — | copies `sorted`, `case_sensitive`, `duplicates` **and** the items from another TStringList (FPC); any other source is rc 1, destination untouched |
| `l.AddStrings src` | — | appends another TStringList's items; a non-TStringList source is rc 1 |

Per-member upstream reference and the roadmap of the members that are **not**
ported (`Names`/`Values`, `Text`/`CommaText`/`DelimitedText`, `LoadFromFile`/
`SaveToFile`, `Objects`/`AddObject`/`OwnsObjects`, `OnChange`/`BeginUpdate`):
[docs/TStringList.md](docs/TStringList.md).

## Behaviour worth knowing

- **`Duplicates` needs `Sorted`.** On an unsorted list every `Add` appends,
  whatever the policy says — that is FPC's rule ("Duplicates does nothing if
  the list is not sorted"), and it is also why `Add` is O(1) there. Before the
  2026-09-06 review the port enforced the policy on unsorted lists via a full
  `IndexOf` per `Add`: 300 Adds cost **16.6 s** against 0.12 s for a `TList`.
  They now cost ~0.17 s unsorted and ~0.47 s sorted (finding G1-03).
- **`sorted = true` sorts.** Setting the flag on a populated list reorders it
  immediately; before the review it left the data untouched, so `Find` and the
  sorted `Add` binary-searched unsorted data and answered wrongly (G1-04).
- **Comparison is not a virtual seam in the hot loops.** `Sort`, `Add`,
  `IndexOf` and `Find` call the plain `TStringList._cmpCore` directly instead
  of dispatching `$this.CompareStrings` per element — a kklass dispatch per
  comparison is what made the old code quadratic *and* slow. `CompareStrings`
  remains the public member and uses the same core, so answers are identical,
  but overriding it in a subclass would not change the sorted paths.
- **Ordering is the ambient locale's** (`[[ < ]]` without `LC_ALL=C`), which is
  the historical behaviour of this unit; the test runners pin `C.UTF-8`.
- **`Find`'s miss encoding** is `-insertionPoint - 1`, so a miss at position 0
  is `-1`. Check `Find`'s rc plus the sign, not the value alone.

## Divergences from FPC (all tested)

| Topic | FPC | here |
|---|---|---|
| `Find` | `Boolean` + `out Index` | one `RESULT`: index, or `-insertionPoint-1` |
| `Add` on `dupError` | raises `EStringListError` | rc 1, list unchanged |
| `Assign` from a non-TStringList | raises `EConvertError` | rc 1, destination untouched (decision R5) |
| `Objects`/`OnChange`/`Text`/`Names` | present | not ported — see docs/TStringList.md |
| `CustomSort` | a TStringList member | inherited from `TList` (same comparator protocol) |

## Tests

`bash kcl/tstringlist/tests/tests.sh` — 192 cases on bash 5.2.37 and 5.3.9.
`017_Contract.sh` holds the kcl contract; `018_ReviewP2.sh` holds the
2026-09-06 review regressions (duplicates only when sorted, the sorting setter,
the `dupIgnore` return value, `Assign` flags, fork-free bulk copies) and the
relative performance gate (300 `Add`s < 10× the same `Add`s on a `TList`).
