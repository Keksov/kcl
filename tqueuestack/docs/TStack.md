# TStack / TObjectStack — upstream FPC API reference

> **Upstream reference, ported: the members marked with a kcl mapping below.**
> This page is the FPC rtl-generics `TStack`/`TObjectStack` API; the normative
> API and contract for the bash port is **[../README.md](../README.md)**, which
> covers all four classes.
>
> * **Ported:** `Push`, `Pop`, `TryPop`, `Peek`, `Extract`, `Clear`, `Count`,
>   `ToArray`, the `on_notify` event with its virtual `Notify` seam, and
>   `TObjectStack`'s ownership — including the FPC quirk that
>   `TObjectStack.Pop` hands back an already-FREED handle, preserved verbatim.
> * **Roadmap:** none. The unit is complete (P0–P5, hardened by kcl review
>   phase P2).
> * **Wontfix** (`../tqueuestack_ledger.json`, `out_of_scope`): as for `TQueue`
>   — allocator knobs, the raw `List` buffer, bulk constructors and generics.
> * **Return contract:** a value comes back in `RESULT`, an empty container is
>   rc 1 with `RESULT=''`, and `ToArray` fills a caller array by nameref —
>   call it **directly**, a `$( )` subshell loses the fill.

Source of truth: FPC `packages/rtl-generics/src/generics.collections.pas` —
`TStack<T>` (declaration :434, impl :2561–2652), `TObjectStack<T>` (:492,
impl :2731–2766), base `TCustomList<T>` (:197: `Notify` :1639, `DoRemove`
:1645, `ToArray` :1629). FPC fpcunit seeds:
`packages/rtl-generics/tests/tests.generics.stack.pas` (TTestSimpleStack core
+ TTestSingleObjectStack ownership) and
`tests.generics.stdcollections.pas` (`Test_TStack_Notification`,
`Test_TObjectStack_Notification`) — mined in tests/005 and tests/006–007.

## Model mapping

A `T` value is any bash string; an owned element is a **kklass instance
handle** (`Free` = `$handle.delete`). Storage is one **dense** indexed array
(only push/pop touch it) → the top is always `count-1`, every op O(1).
`Count` maps to `${#items[@]}`. See [../README.md](../README.md).

## TStack members

| FPC | bash | Notes |
|---|---|---|
| `Create` / `Destroy` (:2602) | `TStack.new s` / `s.delete` | Destroy → Clear → per-item removed events during delete (S6) |
| `Push(AValue)` (:2622) | `s.Push v` | append at the top; notify `added` AFTER the write (S1). No-arg stores `''` |
| `Pop: T` (:2631) | `s.Pop` → RESULT | top; `DoRemove(FLength-1, cnRemoved)`; empty → rc 1, RESULT `''` |
| `Extract: T` (:2644) | `s.Extract` → RESULT | top, action `extracted` (owning variant hands ownership back — no free) |
| `Peek: T` (:2636) | `s.Peek` → RESULT | top, no removal; empty → rc 1 |
| `Clear` (:2608) | `s.Clear` | a Pop LOOP → per-item `removed` events in LIFO order |
| `Count` | `s.Count` → RESULT | `func`, fork-free |
| `OnNotify` event | `s.on_notify` var + `Notify` seam | callback `<inst> <item> <added\|removed\|extracted>`; dangling name = silent no-op |
| `ToArray: TArray<T>` (:1629) | `s.ToArray arr` → RESULT=count | fills a nameref **bottom→top** (seed `TestToArray`: `A[i-1]==IntToStr(i)`); call directly |
| — bash extra | `s.TryPop` → RESULT + rc | like Pop but SILENT on empty |

Not ported (wontfix): capacity family, enumerators, `Create(ACollection)` —
same rationale as [TQueue.md](TQueue.md).

## TObjectStack members

`TObjectStack<T: class> = class(TStack<T>)` (:492) — the owning stack.

| FPC | bash | Notes |
|---|---|---|
| `Create(AOwnsObjects=True)` (:2740) | `TObjectStack.new s [true\|false]` | **owns default TRUE** (FPC :498) |
| `OwnsObjects` property (:504) | `s.owns_objects` (writable) | read at event time (S10) |
| `Notify` override (:2733) | overridden | inherited FIRST (callback sees the instance ALIVE), then free on `removed` only when owning |
| **`function Pop: T`** (:2763) | `s.Pop` → RESULT | ⚠ **the quirk** — see below |

### ⚠ Quirk: `TObjectStack.Pop` returns a freed handle

FPC keeps `Pop` a function (`Result := inherited Pop`, :2763), but by the time
it returns, ownership has already freed the object — FPC hands back a dangling
pointer. This port preserves it verbatim: `s.Pop` returns the **dead handle**
(a string that is safe to hold but dead to dispatch on — its methods are gone).
**To keep the top element alive, use `s.Extract`** — it removes without
freeing.

## Divergences (bash-side, all tested)

| Topic | FPC | here |
|---|---|---|
| empty Pop/Peek | raises `EArgumentOutOfRangeException` | rc 1 + RESULT `''` + debug-only msg |
| Pop of an owned element | dangling pointer | dead handle string (safe to hold, dead to call) |
| free of a dead/garbage handle | crash / UB | silent no-op (liveness guard) |
| capacity / growth policy | tunable | dense array, no API |
| NUL bytes in items | — | unsupported (bash limit) |
