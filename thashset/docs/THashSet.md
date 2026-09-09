# THashSet / TCustomSet — upstream FPC API reference

> **Upstream reference, ported: the members marked with a kcl mapping below.**
> This page is the FPC rtl-generics `TCustomSet<T>` / `THashSet<T>` API; the
> normative API and contract for the bash port is
> **[../README.md](../README.md)**.
>
> * **Ported:** the whole `TCustomSet` public surface that a bash set can have —
>   `Add`, `Remove`, `Extract`, `Contains`, `Clear`, `Count`, the varargs
>   `AddRange`, all four algebra procedures (`UnionWith`, `IntersectWith`,
>   `ExceptWith`, `SymmetricExceptWith`) and the `OnNotify` event — plus
>   `THashSet`'s `Create`/`Destroy`. Bash-only siblings: `ToArray`, `ForEach`,
>   `Assign`, `AddRangeFromArray`, and the virtual `Notify` seam with
>   `_notifyHook`.
> * **Roadmap:** none. The unit is complete (P0–P4).
> * **Wontfix** (`../thashset_ledger.json`, `out_of_scope`): the comparer and
>   capacity family (`Create(const AComparer: IEqualityComparer<T>)` **:562**,
>   `GetCapacity`/`SetCapacity` **:556**/**:557** behind `Capacity` **:523**,
>   `TrimExcess` **:524**/**:573**, and the `TOpenAddressingLP` backend
>   **:535**) — `declare -A` *is* the hash table and a custom equality cannot
>   back its lookups; the sorted family `TSortedSet<T>` (**:839–881**),
>   `TSortedHashSet<T>` (**:883–941**) and the AVL machinery they sit on
>   (`TAVLTree<T>` **:812–824**, `TIndexedAVLTree<T>` **:826–837**,
>   `TCustomAVLTreeMap` **:638**) — a balanced tree buys nothing over a native
>   hash, so ordered iteration is `ToArray` + `TArray.sort` at the boundary
>   (the example is in the README); the enumerator objects
>   (`TCustomSetEnumerator` **:480–489**, `THashSetEnumerator` **:537–543**,
>   `TPointersEnumerator` **:545–552**, `GetEnumerator` **:503**/**:564**,
>   `GetPtrEnumerator` **:554**) — replaced by `ForEach` and `ToArray`; the
>   `TEmptyRecord` value trick (**:535**, `EmptyRecord` **:946**) — internal,
>   this port stores a literal `1`; and elements containing NUL (a bash
>   language limit).
> * **Return contract:** a Boolean member answers with its **exit status** and
>   is silent on `false`; a value comes back in `RESULT`; a rejected operand is
>   rc 1 with nothing printed and nothing mutated; a malformed **call** (a bad
>   output/input array name, a non-function handed to `onNotify`) is rc 2.

Source of truth: FPC `packages/rtl-generics/src/generics.collections.pas` at
the **release_3_2_2** tag — `TCustomSet<T>` (declared **:474–527**, the set
algebra implemented **:2379–2467**) and `THashSet<T>` (declared **:531–574**,
implemented **:2500–2601**). FPC fpcunit seeds:
`packages/rtl-generics/tests/tests.generics.sets.pas` — `Test_Set_General`
**:86–152** (the algebra truth table, entered for `THashSet` from
`Test_HashSet_General` **:231–234**) and
`Test_TCustomSet_Notification` **:261–338** (entered from
`Test_THashSet_Notification` **:340–343**). Both are ported case for case in
`tests/005_SetAlgebra.sh` §A and `tests/006_Events.sh` §A.

> **NB on line numbers.** The `:2815`/`:2853`/`:2861`/`:2878`/`:2886` and
> `:3002`/`:3009`/`:3019`/`:3031` refs recorded at P0 (still visible in a few
> ledger `out_of_scope` strings) came from a **different revision** of the same
> file: the code is identical word for word, only the lines moved. Every number
> on this page is the tag's, re-read at P4.

## Model mapping

`THashSet<T>` is not a hash set with a set implementation — it is a
**dictionary with empty values**:

```pascal
FInternalDictionary: TOpenAddressingLP<T, TEmptyRecord>;   // :535
```

Every member is a one-line delegation to it (**:2559–2601**). The bash port is
therefore the `tdictionary` storage layer with the value dimension deleted:
one `declare -A ${inst}_items` per instance, membership is
`items["k$item"]=1`, and `Count` is `${#items[@]}`. The `k` prefix exists
because bash 5.2 rejects an empty subscript, and `''` must stay a valid
element. `T` collapses to *any bash string*.

The class chain FPC declares:

```pascal
TCustomSet<T>  = class(TEnumerableWithPointers<T>);   // :474
THashSet<T>    = class(TCustomSet<T>);                // :531
TSortedSet<T>  = class(TCustomSet<T>);                // :839  — wontfix
TSortedHashSet<T> = class(TCustomSet<T>);             // :883  — wontfix
```

`TCustomSet` declares `Add`/`Remove`/`Extract`/`Clear`/`Contains` **abstract**
(**:505–510**) and implements `AddRange` and the four algebra procedures
against them (**:2379–2467**). The bash port copies that structure: the algebra
members drive the public `$this.Add` / `$this.Remove` / `$this.Contains`
instead of touching the storage, which is what keeps the event stream identical
to the same calls made by hand.

---

## TCustomSet members

### Add / Remove / Extract — the abstract Boolean trio

```pascal
function Add(constref AValue: T): Boolean; virtual; abstract;      // :505
function Remove(constref AValue: T): Boolean; virtual; abstract;   // :506
function Extract(constref AValue: T): T; virtual; abstract;        // :507
```

Implemented by `THashSet` (below). This is the loud difference from
`TDictionary`, whose `Add` **raises** on a duplicate and whose `Remove` is a
`procedure`: in a set both answers are ordinary Booleans.

**kcl:** `s.Add item` / `s.Remove item` — the Boolean **is** the exit status,
and rc 1 is a silent answer, never an error path. `s.Extract item` → `RESULT`.

### Clear / Contains / Count / Capacity / TrimExcess

```pascal
procedure Clear; virtual; abstract;                                // :509
function Contains(constref AValue: T): Boolean; virtual; abstract; // :510
property Count: SizeInt read GetCount;                             // :522
property Capacity: SizeInt read GetCapacity write SetCapacity;     // :523
procedure TrimExcess; virtual; abstract;                           // :524
```

**kcl:** `s.Clear`, `s.Contains item` (rc 0/1), `s.Count` → `RESULT`
(computed from the storage, so it cannot drift). `Capacity` / `TrimExcess` →
**wontfix**: a bash associative array has no reservable capacity.

### AddRange — four overloads, one AND-fold

```pascal
function AddRange(constref AValues: array of T): Boolean; overload;              // :511, impl :2379
function AddRange(const AEnumerable: IEnumerable<T>): Boolean; overload;         // :512, impl :2388
function AddRange(AEnumerable: TEnumerable<T>): Boolean; overload;               // :513, impl :2397
function AddRange(AEnumerable: TEnumerableWithPointers<T>): Boolean; overload;   // :515, impl :2407
```

```pascal
Result := True;
for i in AValues do
  Result := Add(i) and Result;        // :2383-2385
```

The `and` is on the **right** of the assignment, so nothing is short-circuited:
`Add` runs for every item and the new ones land whatever the answer is. An
empty array leaves `Result` **True**.

**kcl:** `s.AddRange i1 [i2 …]` — the varargs form, rc 0 iff every item was
newly added, **zero arguments is rc 0**, and a duplicate *inside* the argument
list makes it rc 1. The three collection overloads have no bash shape: a whole
set as the source is `s.UnionWith other` (membership) or `s.AddRange` over the
source's `ToArray` output (the Boolean). `s.AddRangeFromArray arrName` is the
bash-only bulk sibling over a caller **indexed** array.

### UnionWith

```pascal
procedure TCustomSet<T>.UnionWith(AHashSet: TCustomSet<T>);   // :517, impl :2417
begin
  for i in AHashSet.Ptr^ do
    Add(i^);
end;
```

One pass over the **operand**. Duplicates are silently skipped by `Add`, so only
genuinely new elements notify.

**kcl:** `s.UnionWith other`. The operand's keys are snapshot before anything is
written, which makes `a.UnionWith a` a defined no-op.

### IntersectWith

```pascal
procedure TCustomSet<T>.IntersectWith(AHashSet: TCustomSet<T>);   // :518, impl :2425
begin
  LList := TList<PT>.Create;
  for i in Ptr^ do
    if not AHashSet.Contains(i^) then
      LList.Add(i);
  for i in LList do
    Remove(i^);
  LList.Free;
end;
```

**Two passes over SELF**: collect this set's non-members of the operand, then
remove them — nothing is deleted while the table is being walked. That is what
makes `a.IntersectWith a` a defined no-op (pass 1 collects nothing).

**kcl:** `s.IntersectWith other`, same two passes over a key snapshot.

### ExceptWith

```pascal
procedure TCustomSet<T>.ExceptWith(AHashSet: TCustomSet<T>);   // :519, impl :2442
begin
  for i in AHashSet.Ptr^ do
    Remove(i^);
end;
```

One pass over the operand; misses are silent. Upstream, `a.ExceptWith a` walks
the argument's live table while removing from it — undefined in the letter.

**kcl:** `s.ExceptWith other` snapshots the operand's keys first, so the
self-case is **defined**: the set is drained empty.

### SymmetricExceptWith

```pascal
procedure TCustomSet<T>.SymmetricExceptWith(AHashSet: TCustomSet<T>);   // :520, impl :2450
begin
  LList := TList<PT>.Create;
  for i in AHashSet.Ptr^ do
    if Contains(i^) then
      LList.Add(i)
    else
      Add(i^);
  for i in LList do
    Remove(i^);
  LList.Free;
end;
```

**Two passes over the OPERAND**: mark the common elements while adding the
operand-only ones, then remove the marked. Hence the deterministic event phase
order (`added` … then `removed` …) and `a.SymmetricExceptWith a` = ∅.

**kcl:** `s.SymmetricExceptWith other`, ported verbatim.

### OnNotify — a property over an abstract pair

```pascal
FOnNotify: TCollectionNotifyEvent<T>;                                  // :476
function GetOnNotify: TCollectionNotifyEvent<T>; virtual; abstract;    // :495
procedure SetOnNotify(AValue: TCollectionNotifyEvent<T>); virtual; abstract;  // :496
property OnNotify: TCollectionNotifyEvent<T> read GetOnNotify write SetOnNotify;  // :526
```

A set has **no** virtual `Notify` in FPC — the whole event surface is this
property, implemented by the concrete class. The three actions come from
`TCollectionNotification = (cnAdded, cnRemoved, cnExtracted)` (**:112**).

**kcl:** `s.on_notify` (the stored callback name, `''` = off),
`s.onNotify name` (the validating setter) and `s.Notify item action` — the
**public virtual seam** the house pattern adds (`tqueuestack`, `tdictionary`),
together with `s._notifyHook` so a descendant that overrides `Notify` receives
events with no user callback attached. Callback signature:
`cb <inst> <item> <added|removed|extracted>`.

### Create(ACollection) / enumerators

```pascal
constructor Create(ACollection: TEnumerable<T>); overload;      // :499, impl :2359
function GetEnumerator: TCustomSetEnumerator; ... abstract;     // :503
function DoGetEnumerator: TEnumerator<T>; override;             // :491, impl :2354
```

`Create(ACollection)` is `Create` followed by an `Add` loop (**:2363–2365**).

**kcl:** `s.Assign src` (replace the contents with a copy of another live
`THashSet`; the operand is checked **by class** before any mutation).
Enumerators → **wontfix**, replaced by `s.ForEach cb` (snapshot semantics) and
`s.ToArray arr` (a lossless nameref fill, `RESULT` = the count).

---

## THashSet members

### Create / Destroy

```pascal
constructor Create; override; overload;                                 // :561, impl :2544
constructor Create(const AComparer: IEqualityComparer<T>); overload;    // :562, impl :2549
destructor Destroy; override;                                           // :563, impl :2554
```

```pascal
constructor THashSet<T>.Create;
begin
  FInternalDictionary := TOpenAddressingLP<T, TEmptyRecord>.Create;   // :2546
end;

destructor THashSet<T>.Destroy;
begin
  FInternalDictionary.Free;                                           // :2556
end;
```

Freeing the internal dictionary runs **its** `Clear`, so a destroyed set
notifies `cnRemoved` once per surviving element (pin S5; the seed proves it at
`tests.generics.sets.pas` **:334–336**).

**kcl:** `THashSet.new s` / `s.delete`. `Destroy` calls `$this.Clear` — the
virtual call, so a descendant that overrides `Clear` or `Notify` is honoured —
and then tears the storage array down. The comparer constructor is **wontfix**.

### Add

```pascal
function THashSet<T>.Add(constref AValue: T): Boolean;   // :566, impl :2559
begin
  Result := not FInternalDictionary.ContainsKey(AValue);
  if Result then
    FInternalDictionary.Add(AValue, EmptyRecord);
end;
```

A duplicate is answered `False` **before** anything is written — no mutation and
no notification (pin S1).

**kcl:** `s.Add item` → rc 0 added / rc 1 duplicate, silent, one `added` event
on a real insert only.

### Remove

```pascal
function THashSet<T>.Remove(constref AValue: T): Boolean;   // :567, impl :2566
begin
  LIndex := FInternalDictionary.FindBucketIndex(AValue);
  Result := LIndex >= 0;
  if Result then
    FInternalDictionary.DoRemove(LIndex, cnRemoved);
end;
```

**kcl:** `s.Remove item` → rc 0 removed / rc 1 absent, silent; the `removed`
event fires **after** the element is gone (a callback's `Contains` is already
false and `Count` is already decremented).

### Extract

```pascal
function THashSet<T>.Extract(constref AValue: T): T;   // :568, impl :2576
begin
  LIndex := FInternalDictionary.FindBucketIndex(AValue);
  if LIndex < 0 then
    Exit(Default(T));            // :2582 — exits BEFORE DoRemove, so a miss is silent
  Result := AValue;
  FInternalDictionary.DoRemove(LIndex, cnExtracted);
end;
```

A miss returns `Default(T)` and is **not** an error (pin S6). For
`T = string` that is `''` — which is also a perfectly good element, so the hit
and the miss are indistinguishable upstream too.

**kcl:** `s.Extract item` → `RESULT` = the element or `''`, **rc 0 either way**;
disambiguate with `Contains` first. A hit fires `extracted`.

### Clear

```pascal
procedure THashSet<T>.Clear;   // :570, impl :2588
begin
  FInternalDictionary.Clear;
end;
```

The dictionary's `Clear` releases the storage **first** and notifies afterwards,
so every callback observes an already-empty set (pin S4).

**kcl:** `s.Clear` — the storage array is emptied first, then one `removed` per
old element; clearing an empty set fires nothing.

### Contains

```pascal
function THashSet<T>.Contains(constref AValue: T): Boolean;   // :571, impl :2593
begin
  Result := FInternalDictionary.ContainsKey(AValue);
end;
```

**kcl:** `s.Contains item` → rc 0 / rc 1, silent either way.

### GetCount / GetCapacity / SetCapacity / TrimExcess

```pascal
function GetCount: SizeInt; override;              // :555, impl :2510
function GetCapacity: SizeInt; override;           // :556, impl :2515
procedure SetCapacity(AValue: SizeInt); override;  // :557, impl :2520
procedure TrimExcess; override;                    // :573, impl :2598
```

**kcl:** `s.Count` → `RESULT`. The capacity three are **wontfix**.

### GetOnNotify / SetOnNotify / InternalDictionaryNotify — the real plumbing

```pascal
procedure THashSet<T>.InternalDictionaryNotify(   // declared :533, impl :2500
  ASender: TObject; constref AItem: T; AAction: TCollectionNotification);
begin
  FOnNotify(Self, AItem, AAction);                // the SENDER is the SET
end;

function THashSet<T>.GetOnNotify: TCollectionNotifyEvent<T>;   // :558, impl :2525
begin
  Result := FInternalDictionary.OnKeyNotify;      // the private FORWARDER
end;

procedure THashSet<T>.SetOnNotify(AValue: TCollectionNotifyEvent<T>);  // :559, impl :2530
begin
  FOnNotify := AValue;
  if Assigned(AValue) then
    FInternalDictionary.OnKeyNotify := InternalDictionaryNotify
  else
    FInternalDictionary.OnKeyNotify := nil;
end;
```

Three consequences, two ported literally:

1. The **sender handed to the callback is the set**, not the storage —
   ported as `"$on_notify" "$__inst__" "$item" "$action"`.
2. With no handler assigned the internal dictionary is **not hooked at all**, so
   nothing is dispatched. That `if Assigned … else nil` is the FPC original of
   the `TSet._notify` gate: the gate is parity, not an optimisation.
3. `GetOnNotify` reads back the private forwarder rather than the handler the
   caller assigned — an upstream asymmetry. **Not** ported: `$(s.on_notify)`
   returns the name that was set (README divergence table).

---

## How the bash port maps

| FPC | kcl | Notes |
|---|---|---|
| `Create` **:561** / `Destroy` **:563** | `THashSet.new s` / `s.delete` | `Destroy` clears first → `removed` per element (S5) |
| `Add` **:566** | `s.Add item` | Boolean → exit status, rc 1 silent |
| `Remove` **:567** | `s.Remove item` | Boolean → exit status, rc 1 silent |
| `Extract` **:568** | `s.Extract item` | `RESULT`; miss = `''` rc 0 (S6) |
| `Contains` **:571** | `s.Contains item` | rc 0/1 |
| `Clear` **:570** | `s.Clear` | empty first, then notify (S4) |
| `Count` **:522** | `s.Count` | `RESULT`, computed |
| `AddRange(array of T)` **:511** | `s.AddRange i1 [i2 …]` | AND-fold; zero args rc 0 |
| `AddRange(TEnumerable<T>)` **:513** | `s.UnionWith` + `s.AddRange` over `ToArray` | no collection type in bash |
| — | `s.AddRangeFromArray arrName` | bash extra; bad name / assoc / scalar / unset = rc 2 |
| `UnionWith` **:517** | `s.UnionWith other` | operand snapshot first |
| `IntersectWith` **:518** | `s.IntersectWith other` | two-pass over self |
| `ExceptWith` **:519** | `s.ExceptWith other` | self-case defined = drain |
| `SymmetricExceptWith` **:520** | `s.SymmetricExceptWith other` | two-pass over the operand |
| `Create(ACollection)` **:499** | `s.Assign src` | class-checked before any mutation |
| `GetEnumerator` **:503** | `s.ForEach cb` / `s.ToArray arr` | snapshot / lossless nameref fill |
| `OnNotify` **:526** | `s.on_notify`, `s.onNotify cb`, `s.Notify item action` | plus `s._notifyHook` for descendants |
| `Capacity` **:523**, `TrimExcess` **:524** | — | wontfix |
| `Create(IEqualityComparer)` **:562** | — | wontfix |
| `TSortedSet` **:839**, `TSortedHashSet` **:883** | `ToArray` + `TArray.sort` | wontfix (README example) |

## Divergences (bash-side, all tested)

| Topic | FPC | here |
|---|---|---|
| element type | generic `T` | any bash string; `''` is a valid element; NUL is impossible |
| the Boolean trio | `Boolean` results | the **exit status**, silent on `false` |
| algebra operand | any `TCustomSet<T>`; anything else fails to compile | checked at run time **by class**: rc 1, nothing printed, set byte-identical |
| `a.ExceptWith a` | walks the argument's live table while removing from it | operand keys snapshot first → defined drain to ∅ |
| reading `OnNotify` back | `GetOnNotify` **:2525** returns the private forwarder | `$(s.on_notify)` returns the name that was assigned |
| the event seam | no virtual `Notify` at all | a public virtual `Notify` + `_notifyHook` (house pattern) |
| assigning a bad handler | will not compile | `s.onNotify bogus` = rc 2, the installed hook kept |
| iteration order | hash order (unspecified) | hash order (bash associative order) — unspecified |
| ordered iteration | `TSortedSet` / `TSortedHashSet` | `s.ToArray arr` + `TArray.sort arr` at the boundary |
