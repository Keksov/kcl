# kcl/tobjectlist — TObjectList for bash: the OWNING list

Port of FPC `contnrs.TObjectList` (`TObjectList = class(TList)`). A `TList` of
**kklass instance handles** whose lifecycle the list manages: with
`owns_objects` (default **true**, as in FPC) every REMOVAL path also frees the
element — `$handle.delete`. This is the genuinely valuable axis in bash:
non-owning vs owning containers (temp files, coprocesses, kklass objects held
by name).

```bash
source kcl/tobjectlist/tobjectlist.sh

TObjectList.new pool             # owning (FPC default)
TStopwatch.new sw1; TStopwatch.new sw2
pool.Add sw1 >/dev/null
pool.Add sw2 >/dev/null

pool.Delete 0                    # removes AND frees sw1
pool.Extract sw2                 # removes WITHOUT freeing (ownership released)
pool.delete                      # frees every still-owned element

TObjectList.new refs false       # non-owning: a plain TList of handles
```

## The ownership contract

Ownership fires exactly where FPC fires `Notify(…, lnDeleted)`:

| Path | Frees? | Notes |
|---|---|---|
| `Delete index` | ✓ the victim | bounds validated BEFORE freeing — an invalid index frees nothing (rc 1, as TList) |
| `Clear` | ✓ all `[0,count)` | |
| `Remove item` | ✓ the found item | miss → RESULT −1, nothing freed |
| `Put index newItem` | ✓ the OLD item | **unless** new == old (FPC TList.Put notifies only when the pointer changes) |
| `BatchDelete index count` | ✓ the clamped range | bash extra — an owning list must not leak through it |
| destructor (`list.delete`) | ✓ all `[0,count)` | the FPC `L.Free` headline |
| `Extract item` | ✗ **never** | removal that RELEASES ownership; RESULT = handle (rc 0) / "" (rc 1) |
| `Add / Insert / Exchange / Move / Sort / CustomSort / Pack` | ✗ | FPC fires no lnDeleted there |

`owns_objects` is a plain readable/writable var (`L.owns_objects = "false"`),
honored at the moment each removal happens — same as FPC's writable
`OwnsObjects` property. Constructor token mirrors `Create(FreeObjects)`:
`TObjectList.new L [true|false]`; an unknown token → rc 1, the list is still a
valid OWNING list (house token convention).

## The `_free` guard — deliberate deltas vs FPC

An element is freed only if it is a **live kklass instance**: the per-instance
dispatcher `<handle>.delete` exists exactly while the instance is alive, so the
guard is `declare -F "$handle.delete"`. Consequences (all pinned by tests):

| Case | FPC | here |
|---|---|---|
| free `nil` / empty string | safe no-op | safe no-op |
| free a garbage pointer / non-instance string | **crash / UB** | **silent no-op** |
| double-free (same handle twice in one list) | crash / UB | **silent no-op** (dispatcher already gone) |

The guard generalizes FPC's `nil.Free`-is-safe rule to every non-live value —
a bash-side softening, never a behavior change for correct programs.

## API

Everything of [`TList`](../tlist/tlist.sh) is inherited (Add/Insert/First/
Last/Get/Put/IndexOf/Sort/CustomSort/Exchange/Move/Pack/Clear/Delete/Remove/
BatchInsert/BatchDelete — removal paths wrapped as above). New members:

| Member | Semantics |
|---|---|
| `TObjectList.new L [true\|false]` | ctor; owns default **true** |
| `L.owns_objects` / `L.owns_objects = v` | the FPC `OwnsObjects` property |
| `L.Extract item` | remove without freeing; RESULT=item rc 0 / "" rc 1 |
| `L.FindInstanceOf Class [exact=true\|false] [startAt=0]` | index of the first element that IS the class (exact) or DESCENDS from it (`false` — walks kklass's parent chain), from `startAt`; RESULT −1 rc 1 on miss. Non-instance elements never match |

Implementation note: every removal override is one line of substance —
`<free if owns>; inherited X "$@"` — kklass's `inherited` composes the parent
behavior, so TList's logic exists in exactly one place (the same
no-duplication principle as the TList→TArray sort delegation).

## Not ported (wontfix)

- `TComponentList`, `TClassList`, `TOrderedList/TStack/TQueue` (same contnrs
  unit) — out of scope; queues/stacks are the tqueuestack roadmap unit.
- The `Notify` seam itself — bash TList has no notification mechanism; the
  removal-path overrides ARE its port.
- `FindInstanceOf` beyond name identity — matching is by kklass class NAME and
  its parent chain; there is no structural class introspection in bash.

## Tests

`tests/001…003` — 31 cases, green on bash 5.2.37 **and** 5.3.9:
ownership core (001), **the 9 FPC fpcunit tests of
`packages/fcl-base/tests/utcobjectlist.pp` adapted verbatim** (002 — handles
for TObjects, `TStringList(:TList)` standing in for `TMyObject(:TObject)`,
dispatcher-liveness for the `IsFreed` destructor flag), and the ownership
torture matrix (003). Rationale per case in
[`TEST_COVERAGE_NOTES.md`](TEST_COVERAGE_NOTES.md).
