# TQueue / TStack (+ TObjectQueue / TObjectStack) → bash port plan (kcl/tqueuestack)

**Roadmap position:** 5/7 (owner priority order, 2026-07-12). One owner-defined block →
one folder/ledger/suite; four classes in one unit file (precedent: tdictionary ships two).
**Source of truth:** FPC rtl-generics `generics.collections.pas` — `TQueue<T>` (:386–433; impl: Enqueue :2521, Dequeue :2530, Extract :2535, Peek :2540, Clear :2548, FLow/MoveToFront), `TStack<T>` (:434–460; impl: Clear :2608, Push :2622, Pop :2631, Peek :2636, Extract :2644), `TObjectQueue<T>` (:477–490; Notify :2696, **`procedure Dequeue`** :2726), `TObjectStack<T>` (:492–505; Notify :2733, **`function Pop: T`** :2763), base `TCustomList<T>` (:197–226: single `OnNotify` event, virtual `Notify` :213, `DoRemove` :1645), `TCollectionNotification` (:140).
**Target:** `kcl/tqueuestack/tqueuestack.sh` — kklass **instantiable** classes `TQueue`, `TStack` (standalone) + `TObjectQueue : TQueue`, `TObjectStack : TStack` (inheritance + override, the tdictionary P6 pattern).
**Ledger:** `kcl/tqueuestack/tqueuestack_ledger.json`.
**Workflow:** phase → dual-bash tests → full master sweep → STOP → "go"; commits gated; no unit edits during a sweep.
**Conventions:** as `kcl/tdictionary/PLAN.md` §2.2–2.4/§6.

---

## 1. Scoping analysis

Thin wrappers over one indexed bash array per instance — the cheapest unit in the
roadmap; all the machinery (events seam, ownership frees, RESULT discipline) is a
straight clone of proven tdictionary architecture. Entirely Tier A.

### Ported

| FPC | bash | Notes |
|---|---|---|
| `TQueue.Create` / `Destroy` | `TQueue.new q` / `q.delete` | Destroy→Clear (notifications fire; pin S6) |
| `Enqueue(AValue)` | `q.Enqueue v` | notify added AFTER the write (:2521–2528) |
| `Dequeue: T` | `q.Dequeue` → RESULT | = DoRemove(head, **removed**) (:2530) |
| `Extract: T` | `q.Extract` → RESULT | = DoRemove(head, **extracted**) (:2535) |
| `Peek: T` | `q.Peek` → RESULT | empty → EArgumentOutOfRange → rc=1 (:2540–2546) |
| `Clear` | `q.Clear` | **loop of Dequeue** → per-item removed events in FIFO order (:2548–2552) — ≠ tdictionary's empty-first-then-notify; honest difference, pinned |
| `Count` | `q.count` | computed property (§2.2) |
| `OnNotify` | `q.onNotify` property + `Notify` virtual seam | cb `<inst> <item> <added|removed|extracted>`; `_notifyHook` guard (tdictionary P5 clone) |
| `TStack.Push/Pop/Peek/Extract/Clear/Count/OnNotify` | same shapes | Pop/Extract from the TOP; Clear = loop of Pop → LIFO removed order (:2608–2612) |
| `TObjectQueue.Create(AOwnsObjects=True)` | `TObjectQueue.new q [false]` | **FPC default owns=true** — kept (documented loudly); ownsObjects read/write property (:489) |
| `TObjectQueue.Notify` override | `override proc Notify` | inherited first, then free on **removed** only (:2696–2701) |
| **`TObjectQueue.Dequeue` is a PROCEDURE** (:488, :2726) | `override proc Dequeue` → RESULT='' | FPC hides the function: the dequeued (possibly freed) object is NOT returned; use Extract to take ownership. Quirk preserved verbatim. |
| `TObjectStack.Notify` override + **`Pop: T`** (:503, :2763) | Pop returns the NAME of a possibly-already-freed instance | FPC returns a dangling pointer here; bash returns a dead handle — safe (a string), documented ("use Extract to keep") |
| `TObjectStack.Create/ownsObjects` | as queue | |

Bash-convenience extras (TEST_COVERAGE_NOTES rows): `q.ToArray outVar` (front→back) /
`s.ToArray outVar` (bottom→top; FPC ToArray exists on TCustomList :218 — order pinned at
P0), `TryDequeue`/`TryPop` sugar (rc instead of error on empty — the Try* house pattern).

### NOT ported (wontfix)

1. **Capacity family** — `Capacity`, `SetCapacity`, `TrimExcess`, `PrepareAddingItem`
   growth policy (:195 golden-ratio), Queue's capacity-halving `MoveToFront` trigger —
   the tdictionary API-v2 precedent verbatim: allocator knobs with nothing to control in
   bash. Internal head-compaction is OURS (amortization, §2.3), not an API.
2. **Enumerators / GetEnumerator / pointer enumerators** (`TPointersEnumerator` etc.) —
   replaced by ToArray fills; no `List: TArrayOfT` raw-buffer property either (exposes
   internal layout incl. consumed head slots — meaningless).
3. **`Create(ACollection)` ctor family** — replaced by explicit Enqueue/Push loops or a
   later `.Assign`-style extra if usage demands (not v1).
4. **cnAdding/cnDeleting/cnExtracting pre-notifications** (:140 six-value enum) — FPC's
   list classes only fire the past-tense trio (verify at P0); we port
   added/removed/extracted, same as tdictionary.
5. **NUL bytes** in items (bash limit).

---

## 2. Design decisions

### 2.1 Storage — one indexed array + head index (queue) / plain top (stack)
`${__inst__}_items` (indexed). **Stack:** pure push/pop keeps indices dense from 0 →
top = `count-1`, all ops O(1). **Queue:** `_head` var (FLow analog); Enqueue appends
(`items+=(…)` lands at max_index+1 automatically), Dequeue reads+unsets `items[_head]`
and increments — consumed slots leave holes, and that is FINE because…

### 2.2 count = computed `${#items[@]}`
`${#arr[@]}` counts SET elements only → holes don't count → live count with zero
bookkeeping (the tdictionary computed-count principle on an indexed array). Pinned by
storage test.

### 2.3 Amortized head compaction (internal, not API)
When `_head` crosses a threshold (e.g. ≥64 AND ≥ live count), reindex:
`items=("${items[@]}"); _head=0` — O(live) occasionally = amortized O(1) per op;
bench proves flat per-op cost over a 10k-element drain. Threshold pinned at P0 with
bench data. (This replaces FPC's MoveToFront/SetCapacity halving — internal policy,
observable only as memory behavior.)

### 2.4 Events — single OnNotify + virtual seam (tdictionary P5/P6 clone)
`onNotify` stored property (bash function name, empty=off); `Notify` = public
overridable proc; hot paths guard `[[ -n $onNotify || -n $_notifyHook ]]`; TObject*
ctors arm `_notifyHook` when owning. Notification fires AFTER the physical mutation
with the removed value passed (DoRemove :1645–1663 — Notify is the tail; verify exact
line at P0). Clear orders: FIFO (queue) / LIFO (stack) — pinned by sequence tests.

### 2.5 Empty-collection errors
Dequeue/Pop/Extract/Peek on empty → FPC raises `EArgumentOutOfRangeException` (Peek
explicitly :2542; DoRemove index check :1647) → rc=1, `kk._return ""` (funcs), debug-only
msg. Try* extras return rc=1 silently by design (an answer, not an error).

### 2.6 Ownership (TObject*) — the tdictionary P6 pattern verbatim
`_free` helper: `declare -F "$1.delete"` liveness check → `$1.delete`; free on
action==removed ONLY (Extract hands back; :2696/:2733 = inherited-then-free, user
callback observes the instance ALIVE). FPC ctor default `AOwnsObjects=True` is KEPT
(divergence from tdictionary's explicit tokens — but FPC's own signature defaults true
here, and porting-compat wins; `TObjectQueue.new q false` disables). `ownsObjects`
read/write property (FPC has it writable :489 — mid-life flip test included).

### 2.7 The two FPC quirks are preserved, not "fixed"
- `TObjectQueue.Dequeue` returns NOTHING (procedure) even with ownsObjects=false.
- `TObjectStack.Pop` returns the handle of an instance that ownership just freed.
Both documented with a warning box + "use Extract" guidance. Parity over ergonomics;
the Try*/Extract paths are the ergonomic escape.

## 3. Pinned semantics (verify/finalize at P0)

| # | Semantic | Source | Status |
|---|---|---|---|
| S1 | Enqueue/Push: write THEN notify added | :2521–2528 / :2622–2629 | pinned |
| S2 | Dequeue/Pop/Extract = DoRemove(head/top, removed/extracted); notify AFTER removal, value passed | :2530–2538 / :2631–2647 / :1645–1663 | verify Notify tail position |
| S3 | Peek empty → EArgumentOutOfRange; Dequeue/Pop empty likewise via DoRemove | :2540–2546 / :1647 | pinned |
| S4 | Queue Clear = Dequeue-loop (FIFO removed events) + FLow reset; Stack Clear = Pop-loop (LIFO) | :2548–2552 / :2608–2612 | pinned |
| S5 | Only cnAdded/cnRemoved/cnExtracted fire on these classes | :140 + impl scan | verify (no pre-events) |
| S6 | Destroy → Clear (events fire during delete) | TQueue.Destroy ~:2553 / TStack.Destroy | verify |
| S7 | TObject* Notify: inherited first, free on removed only | :2696–2701 / :2733–2738 | pinned |
| S8 | TObjectQueue.Dequeue procedure / TObjectStack.Pop returns freed handle | :2726–2729 / :2763–2766 | pinned |
| S9 | ToArray order (queue front→back; stack bottom→top) | TCustomList.ToArray :218 + layouts | verify |
| S10 | ownsObjects writable mid-life | :489 / :504 | pinned |

## 4. Parity & test model

Seeds: rtl-generics/tests scanned for queue/stack fpcunit coverage at P0
(tests.generics.stdcollections.pas is the likely host — mined). Basis: S1–S10 pins +
matrices: FIFO/LIFO orderings incl. interleaved Enqueue/Dequeue (wrap the head), event
sequence recorders (tdictionary 011-style), empty-error paths, Try* sugar, exotic values
('', newline, glob, `$(...)`), ownership matrix (none/owns × Dequeue/Pop/Extract/Clear/
delete/overflow of quirks S8), mid-life ownsObjects flip, head-compaction invisibility
(values/order identical across the threshold), zero-fork PATH='', dual-bash, and the
tdictionary $()-mutation caveat respected in every test (stderr via file redirect).
Non-FPC cases → TEST_COVERAGE_NOTES rows.

## 5. Phases

- **P0 — pins + skeleton + storage probes.** Resolve S2/S5/S6/S9 verify-rows; freeze
  compaction threshold policy; skeleton (4 classes, ctor forms) + runner; sparse-count
  and head-hole probes on both bashes; baseline re-measure. STOP.
- **P1 — TQueue core.** Enqueue/Dequeue/Extract/Peek/Clear/count + TryDequeue + ToArray;
  compaction amortization behavior; FIFO matrices. Sweep gate. STOP.
- **P2 — TStack core.** Push/Pop/Extract/Peek/Clear/count + TryPop + ToArray; LIFO
  matrices. Sweep gate. STOP.
- **P3 — events.** onNotify property + Notify seam + `_notifyHook` on both classes;
  S1/S2/S4 sequence tests (recorder callbacks); dangling-cb/rc-ignored edges. Sweep gate. STOP.
- **P4 — TObjectQueue/TObjectStack.** Inheritance + overrides + ownership matrix +
  the S8 quirks + mid-life flip. Sweep gate. STOP.
- **P5 — docs, bench, closeout.** README (both classes, quirk warning boxes),
  docs/TQueue.md + docs/TStack.md (upstream FPC references per kcl docs convention —
  one file per type), bench.sh (Enqueue/Dequeue/Push/Pop per-op, 10k drain flatness =
  compaction proof, vs tlist.Add reference, zero-fork), TEST_COVERAGE_NOTES finalized,
  ledger COMPLETE, final sweep. STOP.

## 6. Bash traps to respect

1. `${__inst__}_items` naming (NEVER `_data` — kklass property store; tdictionary P0 lesson).
2. Sparse-array arithmetic: top index of a stack = count-1 ONLY because stack ops keep
   it dense — never generalize to the queue side, where holes exist by design.
3. `items+=(v)` appends after the HIGHEST index — exactly what the queue tail needs;
   never write `items[${#items[@]}]=v` (wrong under holes).
4. `unset 'items[$__idx]'` single-quoted (expanded once; idx is numeric — still keep the
   house idiom).
5. `kk._return ""` on every func fail path (Dequeue/Pop/Extract/Peek empty).
6. Recorder-callback tests: direct calls + file-redirect stderr (the $() subshell caveat).
7. Compaction must not run while ForEach-style iteration is added later — no iteration
   API in v1 beyond ToArray snapshot, so safe; note kept for future extension.
8. Never edit the unit mid-sweep.

## 7. Deliverables

`kcl/tqueuestack/`: tqueuestack.sh (4 classes), PLAN.md, tqueuestack_ledger.json,
README.md, docs/TQueue.md, docs/TStack.md, bench.sh, TEST_COVERAGE_NOTES.md,
tests/001…+tests.sh.
