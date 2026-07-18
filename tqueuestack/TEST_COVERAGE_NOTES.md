# tqueuestack — test coverage notes

**Status: FINALIZED at P5 (2026-07-18).** Suite 001–007 = 76 cases, green on
bash 5.2.37 AND true 5.3.9.

Protocol (house): **invented / source-pinned** cases get a row here;
**FPC-traceable** cases cite their seed procedure. Seeds:
`tests.generics.queue.pas` (TTestSimpleQueue, TTestSingleObjectQueue),
`tests.generics.stack.pas` (mirror), `tests.generics.stdcollections.pas`
(`Test_T{Queue,Stack,ObjectQueue,ObjectStack}_Notification`). The S-column
cites the PLAN §3 pin (which carries the generics.collections.pas line anchor).
Classes: `contract` (rc/RESULT/gate/zero-fork), `order` (FIFO/LIFO/ToArray),
`event` (Notify sequences), `own` (TObject* ownership).

## 001 — skeleton / ctor core (P0)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 001.q-init | Create | queue: items+qhead init, Count 0 | contract | storage §2.1 / Q1 |
| 001.s-init | Create | stack: Count 0, on_notify empty | contract | storage |
| 001.count-holes | Count | computed count ignores holes | contract | Q1 |
| 001.owns-default | TObjectQueue.Create | owns default TRUE; explicit false | own | S10 / FPC :483 |
| 001.owns-bogus | TObjectStack.Create | bogus token rc 1, still valid+owning | own | token convention |
| 001.inherit | — | both pairs chain to their base | contract | kklass inheritance |
| 001.inherit-storage | — | TObject* inherit storage via inherited ctor | contract | inherited |
| 001.override-empty | Dequeue/Pop | empty ObjectQueue.Dequeue/ObjectStack.Pop rc 1 | contract | S3 |
| 001.teardown | delete | storage arrays unset | contract | dtor |
| 001.resource | — | re-source no-op | contract | guard |
| 001.zero-fork | Create/Count/delete | ctors/Count/teardown under PATH='' | contract | builtins only |

## 002 — TQueue core (P1, invented/source-pinned)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 002.fifo | Enqueue/Dequeue | FIFO order then empty rc 1 | order | S2/S3 |
| 002.interleave | Dequeue/Enqueue/Peek/ToArray | dequeue-then-enqueue over head holes keeps FIFO | order | storage Q2 |
| 002.extract | Extract | removes front like Dequeue | order | S2 |
| 002.clear | Clear/TryDequeue/Peek | drain + reusable; Try silent, Peek rc 1 | contract | S4 |
| 002.empty-item | Dequeue | ''-item rc 0 vs empty-queue rc 1 | contract | distinction |
| 002.exotic | Enqueue/Dequeue | spaces/newline/glob/$()/unicode byte-exact | order | torture |
| 002.compaction | Enqueue/Dequeue | reindex at threshold; order/values intact | contract | §2.3 / Q3 |
| 002.drain-reset | Dequeue | drain-to-empty resets qhead | contract | Q7 |
| 002.isolation | — | two queues independent | contract | per-instance |
| 002.zero-fork | all | full queue lifecycle under PATH='' | contract | builtins only |

## 003 — FPC TTestSimpleQueue parity (FPC-TRACEABLE)

| ID | Members | Case | Basis (seed proc / line) |
|---|---|---|---|
| 003.empty | Count | fresh Count 0 | TestEmpty :180 |
| 003.add | Enqueue/Count | DoAdd(1)→1, DoAdd(1,1)→2 | TestAdd :198 |
| 003.clear | Clear | add 3, clear, 0 | TestClear :207 |
| 003.getvalue | Dequeue | 1,2,3 then EArgumentOutOfRange analog | TestGetValue :285 |
| 003.peek | Peek/Dequeue | peek==dequeue pairs 1..3 | TestPeek :297 |
| 003.dequeue | Dequeue/Count | Dequeue '1', Count 2 | TestDequeue :322 |
| 003.toarray | ToArray | len 3, elems 1,2,3 front→back | TestToArray :330 |

## 004 — TStack core (P2, invented/source-pinned)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.lifo | Push/Pop | LIFO order then empty rc 1 | order | S2/S3 |
| 004.interleave | Push/Pop/Peek/ToArray | mixed keeps LIFO + density | order | density |
| 004.density | — | indices stay 0..count-1 after mixed ops | contract | dense invariant |
| 004.extract | Extract | removes top like Pop | order | S2 |
| 004.clear | Clear/TryPop/Peek | drain + reusable; Try silent, Peek rc 1 | contract | S4 |
| 004.empty-item | Pop | ''-item rc 0 vs empty rc 1 | contract | distinction |
| 004.exotic | Push/Pop | exotic values byte-exact (LIFO) | order | torture |
| 004.isolation | — | queue vs stack independent | contract | per-instance |
| 004.deep | Push/Pop | 200-deep order-exact drain | order | scale |
| 004.zero-fork | all | stack lifecycle under PATH='' | contract | builtins only |

## 005 — FPC TTestSimpleStack parity (FPC-TRACEABLE)

| ID | Members | Case | Basis (seed proc) |
|---|---|---|---|
| 005.empty | Count | fresh Count 0 | TestEmpty :190 |
| 005.add | Push/Count | 1 then 2 | TestAdd :206 |
| 005.clear | Clear | 3 → 0 | TestClear :215 |
| 005.getvalue | Pop | 3,2,1 then EArgumentOutOfRange analog | TestGetValue :293 |
| 005.peek | Peek/Pop | peek==pop pairs 3..1 | TestPeek :305 |
| 005.pop | Pop/Count | 3,2,1 + Count 0 | TestPop :330 |
| 005.toarray | ToArray | A[i-1]==i bottom→top | TestToArray :345 |

## 006 — events (P3)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 006.q-added | Enqueue | added ×3 in order | event | TestValueNotification (queue) :368 |
| 006.action-split | Dequeue/Extract | removed vs extracted | event | stdcollections :639 |
| 006.q-clear | Clear | removed FIFO | event | TestValueNotificationDelete :376 |
| 006.sender | Enqueue | sender == instance handle | event | callback signature |
| 006.try-silent | TryDequeue | one event; empty fires nothing | event | Try* semantics |
| 006.q-destroy | delete | Destroy fires FIFO removed | event | S6 |
| 006.s-stream | Push/Pop/Extract | stack added + removed + extracted stream | event | stdcollections |
| 006.s-clear | Clear | removed LIFO | event | TestValueNotificationDelete (stack) |
| 006.s-destroy | delete | Destroy fires LIFO removed | event | S6 |
| 006.gate | — | no callback → ops work, nothing dispatched | contract | hot-path gate §2.4 |
| 006.dangling | Notify | dangling callback silent, ops unaffected | contract | robustness |
| 006.result-iso | Notify | RESULT survives a clobbering callback | contract | dispatch rollback |
| 006.exotic-event | — | exotic values through events byte-exact | event | torture |
| 006.detach | on_notify | detach mid-life stops events | event | writable var |
| 006.zero-fork | — | events under PATH='' | contract | builtins only |

## 007 — TObject* ownership (P4; FPC-TRACEABLE where cited)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 007.empty | Count/owns | owning queue Count 0, owns true | own | TestEmpty :99 |
| 007.free-dq | Dequeue | owning Dequeue frees | own | TestFreeOnDeQueue :127 |
| 007.dq-quirk | Dequeue | Dequeue returns NOTHING (RESULT untouched) | own | S8 :2726 |
| 007.no-free | Dequeue/owns | S10 flip owns=false → not freed | own | TestNoFreeOnDeQueue :136 |
| 007.extract | Extract | hands ownership back, never frees | own | S7 |
| 007.try-free | TryDequeue | frees like Dequeue | own | S7 |
| 007.clear-destroy | Clear/delete | free all + free the rest | own | S6/S7 |
| 007.pop-quirk | Pop | returns the DEAD handle (owning) | own | S8 :2763 |
| 007.pop-live | Pop | non-owning returns a LIVE handle | own | S8 |
| 007.s-extract | Extract | stack Extract never frees | own | S7 |
| 007.cb-alive | Notify | callback observes ALIVE; freed after | own | S7 (inherited first) |
| 007.dup | Clear | duplicate handle freed once | own | liveness guard |
| 007.non-instance | Clear | plain strings / '' safe | own | liveness guard |
| 007.empty-dq | Dequeue | empty ObjectQueue.Dequeue rc 1 | own | quirk keeps error |
| 007.fifo-free | delete | FIFO free order via events | own | S6 |
| 007.zero-fork | — | ownership cycle under PATH='' | contract | builtins only |

## Deliberately NOT covered (documented elsewhere)

- Capacity/growth/enumerators — wontfix (ledger out_of_scope; docs).
- Performance thresholds — no hard-ms asserts (flake-prone under sweep load,
  house lesson); `bench.sh` reports honest numbers, incl. the compaction-
  flatness proof and the reviewed non-owning-object dispatch cost.
- `set -e` consumer safety is exercised ad hoc (review round), not in the
  suite; the `_qremove` pre-increment fix removed the one landmine.
