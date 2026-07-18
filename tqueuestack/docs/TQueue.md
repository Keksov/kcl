# TQueue / TObjectQueue — upstream FPC API reference

Source of truth: FPC `packages/rtl-generics/src/generics.collections.pas` —
`TQueue<T>` (declaration :386, impl :2404–2559), `TObjectQueue<T>` (:477,
impl :2694–2729), base `TCustomList<T>` (:197: `Notify` :1639, `DoRemove`
:1645, `ToArray` :1629). FPC fpcunit seeds:
`packages/rtl-generics/tests/tests.generics.queue.pas` (TTestSimpleQueue core
+ TTestSingleObjectQueue ownership) and
`tests.generics.stdcollections.pas` (`Test_TQueue_Notification`,
`Test_TObjectQueue_Notification`) — mined in tests/003 and tests/006–007.

## Model mapping

A `T` value is any bash string; an owned element is a **kklass instance
handle** whose `Free` is `$handle.delete`. FPC's `FLow` (the consumed-front
index) maps to the per-instance `qhead`; storage is one indexed array with
holes behind `qhead`. `Count = FLength - FLow` maps to `${#items[@]}` (set
elements only). See [../README.md](../README.md) for the storage/compaction
design.

## TQueue members

| FPC | bash | Notes |
|---|---|---|
| `Create` / `Destroy` (:2515) | `TQueue.new q` / `q.delete` | Destroy → Clear → per-item removed events fire during delete (S6) |
| `Enqueue(AValue)` (:2521) | `q.Enqueue v` | append at the tail; notify `added` AFTER the write (S1). No-arg stores `''` |
| `Dequeue: T` (:2530) | `q.Dequeue` → RESULT | front; `DoRemove(FLow, cnRemoved)`; empty → rc 1, RESULT `''` |
| `Extract: T` (:2535) | `q.Extract` → RESULT | front, action `extracted` (owning variant hands ownership back — no free) |
| `Peek: T` (:2540) | `q.Peek` → RESULT | front, no removal; empty → rc 1 |
| `Clear` (:2548) | `q.Clear` | a Dequeue LOOP → per-item `removed` events in FIFO order (not a bulk wipe) + head reset |
| `Count` (:2492) | `q.Count` → RESULT | `func`, fork-free (no property-read fork) |
| `OnNotify` event | `q.on_notify` var + `Notify` seam | callback `<inst> <item> <added\|removed\|extracted>`; dangling name = silent no-op; rc ignored |
| `ToArray: TArray<T>` (:1629) | `q.ToArray arr` → RESULT=count | fills a nameref **front→back** (enumerator starts at FLow, :2397); call directly |
| — bash extra | `q.TryDequeue` → RESULT + rc | like Dequeue but SILENT on empty (rc 1 is an answer) |

Not ported (wontfix): the capacity family (`Capacity`/`SetCapacity`/
`TrimExcess`/`PrepareAddingItem` growth policy, `MoveToFront`) — allocator
knobs with nothing to control in bash; the internal compaction replaces them.
Enumerators / `GetEnumerator` / pointer enumerators — replaced by `ToArray`.
`Create(ACollection)` — use an Enqueue loop.

## TObjectQueue members

`TObjectQueue<T: class> = class(TQueue<T>)` (:477) — the owning queue.

| FPC | bash | Notes |
|---|---|---|
| `Create(AOwnsObjects=True)` (:2703) | `TObjectQueue.new q [true\|false]` | **owns default TRUE** (FPC :483, kept verbatim) |
| `OwnsObjects` property (:489) | `q.owns_objects` (writable) | read AT EVENT TIME — a mid-life flip is honored (S10) |
| `Notify` override (:2696) | overridden | inherited FIRST (callback sees the instance ALIVE), then free on `removed` only when owning |
| **`procedure Dequeue`** (:2726) | `q.Dequeue` | ⚠ **the quirk** — see below |

### ⚠ Quirk: `TObjectQueue.Dequeue` returns NOTHING

FPC hides the function behind `procedure Dequeue` (:2726): the dequeued — and,
when owning, **already-freed** — object is not returned. This port preserves
it verbatim: `q.Dequeue` leaves the caller's `RESULT` untouched (it is a
`proc`; the kklass dispatch-rollback restores RESULT). rc still passes through
(empty → rc 1). **To take ownership of the front element, use `q.Extract`** —
it removes without freeing and returns the handle.

## Divergences (bash-side, all tested)

| Topic | FPC | here |
|---|---|---|
| empty Dequeue/Peek | raises `EArgumentOutOfRangeException` | rc 1 + RESULT `''` + debug-only msg |
| free of a dead/garbage handle | crash / UB | silent no-op (liveness guard `declare -F $h.delete`) |
| capacity / growth policy | tunable | internal amortized compaction, no API |
| NUL bytes in items | — | unsupported (bash limit) |
