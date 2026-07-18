# kcl/tqueuestack — TQueue / TStack (+ owning variants) for bash

A bash port of FPC `rtl-generics` `generics.collections.pas`: **four classes
in one unit** — `TQueue` (FIFO) and `TStack` (LIFO), plus their owning
subclasses `TObjectQueue : TQueue` and `TObjectStack : TStack` that
auto-`.delete` handle elements on removal. kklass instantiable classes:

```bash
source kcl/tqueuestack/tqueuestack.sh

TQueue.new q
q.Enqueue alpha; q.Enqueue beta
q.Peek                 # RESULT="alpha"   (front, no removal)
q.Dequeue              # RESULT="alpha"   (FIFO)
q.Count                # RESULT=1

TStack.new s
s.Push one; s.Push two
s.Pop                  # RESULT="two"     (LIFO)

# ownership: elements are kklass instances; the queue frees them on removal
TObjectQueue.new pool          # owns by default (FPC-faithful)
TWorker.new w1; pool.Enqueue w1
pool.Dequeue                   # w1 is freed (see the quirk below)
pool.delete                    # frees every still-queued worker
```

## Design (storage + events)

- **Storage** — one indexed array per instance (`${inst}_items`). A **stack**
  is dense (only push/pop touch it) so the top is always `count-1`; every op
  is O(1). A **queue** keeps a head index (`qhead`, FPC's `FLow`): Enqueue
  appends, Dequeue reads + unsets `items[qhead]` and advances — consumed slots
  become holes. `Count == ${#items[@]}` counts set elements only, so holes
  don't count — a live count with zero bookkeeping. All in-memory ops are
  **fork-free**.
- **Amortized compaction** (internal, not an API — it replaces FPC's
  `MoveToFront`/capacity machinery): when `qhead` crosses 64 *and* reaches the
  live count, the queue reindexes (`items=("${items[@]}"); qhead=0`) — an
  O(live) copy that happens rarely enough to be **amortized O(1) per op**. The
  bench proves it: a 10k drain costs the same per-op as a 1k drain.
- **Events** — a single `on_notify` callback (a function name; `''` = off) and
  an overridable `Notify` seam. A hot-path gate means instances with no
  listener pay just one `[[ ]]` test per mutation, no dispatch. The callback
  fires with `<inst> <item> <added|removed|extracted>` **after** the physical
  mutation (the FPC `DoRemove` tail position). `Clear` and `Destroy` fire
  per-item `removed` events in FIFO (queue) / LIFO (stack) order.

## API

Both classes: `new x` / `x.delete` · `x.Count` · `x.Peek` · `x.Extract` ·
`x.Clear` · `x.ToArray arr` · `x.on_notify` (var). Queue adds `Enqueue` /
`Dequeue` / `TryDequeue`; stack adds `Push` / `Pop` / `TryPop`. Owning
variants add `x.owns_objects` (writable). Read-returning members set `RESULT`;
`ToArray` fills a caller-named array (**call it directly** — a `$()` capture
discards the fill) and returns the count. Removals on an empty collection →
rc 1 + `RESULT=''`; the `Try*` forms are the silent equivalent.

Per-member upstream references: [docs/TQueue.md](docs/TQueue.md) ·
[docs/TStack.md](docs/TStack.md).

## ⚠ Two FPC quirks are preserved verbatim (not "fixed")

FPC's owning variants have two sharp edges. This port keeps them for parity;
**`Extract` is the ergonomic escape** in both cases.

> **`TObjectQueue.Dequeue` returns NOTHING.** FPC declares it a `procedure`
> (:2726): the dequeued (and, when owning, already-freed) object is not
> returned. Here `pool.Dequeue` leaves `RESULT` untouched. **Use
> `pool.Extract` to take ownership** of the front element (removes without
> freeing, returns the handle).

> **`TObjectStack.Pop` returns a FREED handle.** FPC hands back a dangling
> pointer (:2763); here you get a **dead handle string** — safe to hold, but
> its methods are gone. **Use `pool.Extract` to keep the top element alive.**

`owns_objects` is writable mid-life and read at event time, so
`pool.owns_objects = "false"` disowns everything queued thereafter (FPC's
`TestNoFreeOnDeQueue`).

## Divergences from FPC (all tested)

| Topic | FPC | here |
|---|---|---|
| empty Dequeue/Pop/Peek | raises `EArgumentOutOfRange` | rc 1 + `RESULT=''` + debug-only msg |
| free of a dead/garbage handle | crash / UB | silent no-op (liveness guard) |
| capacity / growth / `TrimExcess` | tunable | internal compaction, no API |
| enumerators, `Create(ACollection)` | present | replaced by `ToArray` / explicit loops |
| date/binary/NUL in items | — | unsupported (bash byte strings) |

## Performance (bench.sh, bash 5.2.37; times per op)

`bench.sh` dog-foods `TStopwatch`. Representative numbers:

- **Enqueue/Dequeue ~0.43–0.58 ms/op, Push/Pop ~0.40–0.48 ms/op** — flat from
  n=1000 to n=5000 (kklass dispatch dominates; the data op is trivial).
- **Compaction proof**: a 10k enqueue+drain runs ~0.49 ms/op — *the same* as a
  1k drain, confirming the reindex is amortized O(1), not O(n) per op.
- `Clear` of a large queue is ~10× cheaper per element (~0.05 ms/el, tight
  `_qremove` loop, no per-op method dispatch); the mid-drain reindex adds ~one
  small array copy and is not measurable against the per-element removals.
- **Non-owning `TObjectQueue`/`TObjectStack` cost ~4× a plain queue per op**
  (~1.6 vs ~0.42 ms/op): they always dispatch the virtual `Notify` (a no-op
  when not owning and no callback), because ownership is a *writable* flag that
  the hot-path gate must re-check at event time (S10). The **owning** case —
  the reason these classes exist — pays that dispatch anyway (to free). Plain
  `TQueue`/`TStack` are unaffected. If you need a non-owning object collection
  in a hot loop, prefer a plain `TQueue`/`TStack` of handles and free them
  yourself.

Built for collection-scale work; the per-op cost is kklass dispatch, not the
data structure. Positioned as a faithful, fork-free, event-capable
FIFO/LIFO with optional ownership — not a high-throughput ring buffer.

## Tests

`tests/001…007` — 76 cases, green on bash 5.2.37 **and** true 5.3.9: skeleton
(001), TQueue core + FPC `TTestSimpleQueue` parity (002–003), TStack core +
`TTestSimpleStack` parity (004–005), events with recorded sequences +
`Test_T{Queue,Stack}_Notification` (006), and ownership +
`TTestSingleObject{Queue,Stack}` (007). Per-case rationale in
[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md).
