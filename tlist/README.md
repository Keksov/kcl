# kcl/tlist — TList for bash

A bash port of Free Pascal's `Classes.TList` as a kklass **instantiable**
class. FPC's `TList` holds untyped pointers; a bash list holds **strings**, so
the indexed accessors (`Get`/`Put`/`First`/`Last`) are real values rather than
pointer arithmetic, and `IndexOf` compares strings.

```bash
source kcl/tlist/tlist.sh

TList.new l
l.Add alpha            # RESULT=0  — the INDEX of the new element (FPC)
l.Add beta             # RESULT=1
l.Insert 1 gamma       # alpha | gamma | beta
l.Get 2                # RESULT="beta"   (direct call prints nothing)
l.IndexOf gamma        # RESULT=1        (-1 when absent)
l.count                # 3               (a property: $(l.count) prints it)
l.Delete 0
l.Sort                 # byte order; l.CustomSort myCmp for anything else
l.delete               # destructor: frees the storage array too
```

It is also the base class of [`tstringlist`](../tstringlist/README.md)
(sorting, duplicates, case folding) and
[`tobjectlist`](../tobjectlist/README.md) (owning list of kklass instances).

## Contract

This unit follows the [kcl contract](../README.md#1-the-kcl-contract):

- **Values come back in `RESULT`.** A direct call prints nothing; `$(l.Get 0)`
  prints the value exactly once but forks and loses any mutation. Elements are
  data — `-e`, `-n`, embedded newlines and backslashes all round-trip.
- **Errors are `rc 1` and nothing else** — no stdout, no stderr (a diagnostic
  appears only under `VERBOSE_KKLASS=debug`), and no partial state.
- **Indices are validated** before they reach `(( ))` (`kk.isInt`): a
  non-numeric or injection-shaped index is rc 1, never element 0, and never an
  evaluated command substitution. `08` is decimal 8, not an octal error.
- **`set -eu` clean**, loadable and re-loadable.
- **No forks** on any member's path.
- **`l.delete` frees everything**, `${l}_items` included.

## API

`capacity` and `count` are read/write properties; everything else is a method.

| Member | Result | Notes |
|---|---|---|
| `TList.new l` / `l.delete` | — | the destructor releases `${l}_items` |
| `l.count` / `l.count = N` | count | writing shrinks (dropping the tail) or pads with `''` |
| `l.capacity` / `l.capacity = N` | capacity | a logical reservation; **`N < count` or `N < 0` → rc 1, unchanged** (FPC `EListError`) |
| `l.Add v` | **index** of the new element | grows the capacity as needed |
| `l.Insert i v` | — | `i` in `[0,count]`, else rc 1 |
| `l.Delete i` | — | `i` in `[0,count)`, else rc 1 |
| `l.Remove v` | removed index, or `-1` | first occurrence |
| `l.Clear` | — | count and capacity to 0, storage emptied |
| `l.Get i` / `l.Put i v` | element / — | bounds `[0,count)`, else rc 1 with `RESULT` untouched |
| `l.First` / `l.Last` | element | empty list → rc 1 |
| `l.IndexOf v` | index or `-1` | linear, exact string match |
| `l.Exchange i j` / `l.Move from to` | — | both indices validated |
| `l.Pack` | — | drops empty (`''`) elements |
| `l.Sort` | — | byte order (a bash convenience — FPC's `TList.Sort` always needs a comparator) |
| `l.CustomSort cmpFn` | — | FPC `Sort(Compare)`; stable mergesort via [`TArray.sort`](../tarray/README.md) |
| `l.Grow` / `l.Expand` | — | capacity growth policy (4 → ×2 → ×1.5) |
| `l.BatchInsert i v…` / `l.BatchDelete i n` | — (rc only) | bash extras: one shift for many elements. Their bodies compute the new count into `RESULT`, but both members are declared `proc`, so the value never reaches the caller — read `l.count` instead (recorded as `found_in_P2` in `kcl_ledger.json`) |
| `l.Find` / `l.Assign src` | — | **stubs**: rc 1, list untouched. Implemented in `TStringList` |

The comparator protocol for `CustomSort` is `TArray`'s and is carried by the
**exit status**, so it is fork-free:

```bash
bylen() { (( ${#1} <  ${#2} )) && return 0     # a < b
          (( ${#1} == ${#2} )) && return 1     # a == b
          return 2; }                          # a > b
l.CustomSort bylen
```

Per-member upstream reference (and the map of what is *not* ported):
[docs/TList.md](docs/TList.md).

## Divergences from FPC (all tested)

| Topic | FPC | here |
|---|---|---|
| element type | untyped pointer | string (so `Get`/`Put` are meaningful) |
| out-of-range index | raises `EListError` | rc 1, state unchanged |
| `Capacity < Count` | raises `EListError` | rc 1, state unchanged (decision R2) |
| `Assign(ListA, op, ListB)` | set algebra over two lists | not ported; the stub fails **without** clearing (finding G1-07c) |
| `Extract`/`ExtractItem`/`RemoveItem` | pointer identity / direction | not ported (`TObjectList.Extract` is) |
| `Notify`, enumerators, `List` | present | not ported — see docs/TList.md |
| `BatchInsert`/`BatchDelete` | — | bash extras |

## Tests

`bash kcl/tlist/tests/tests.sh` — 133 cases on bash 5.2.37 and 5.3.9.
`020_Contract.sh` holds the kcl contract (`set -eu`, injection, value
round-trip, caller-variable isolation, lifecycle); `021_ReviewP2.sh` holds the
2026-09-06 review regressions (destructor, `Add` returning the index, the
capacity guard).
