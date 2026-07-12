# TDictionary / TObjectDictionary — upstream FPC API reference

Source of truth: FPC rtl-generics, unit `Generics.Collections`
(`packages/rtl-generics/src/inc/generics.dictionariesh.inc`, interface;
`generics.dictionaries.inc`, implementation — line references below are into
these files). Package docs: <https://www.freepascal.org/docs-html/current/>
(rtl-generics). Copyright (c) 2014 Maciej Izak (hnb) / NewPascal, sponsored by
Sphere 10 Software.

Class chain, as declared:

```pascal
TDictionary<TKey, TValue>       = class(TOpenAddressingLP<TKey, TValue>);        // :668
TObjectDictionary<TKey, TValue> = class(TObjectOpenAddressingLP<TKey, TValue>);  // :669
```

`TOpenAddressingLP` descends from `TOpenAddressing` → `TCustomDictionary`.
This document lists every public member of that chain that is visible on
`TDictionary`, with its kcl/bash mapping. Members whose mechanics have no bash
counterpart are marked **wontfix** with the reason (see also PLAN.md §1).
Generic parameters collapse to bash strings: `TKey = TValue = string`.

kcl mapping conventions: FPC exceptions → `return 1` (message under
`VERBOSE_KKLASS=debug`); function results → echo + `RESULT`; booleans → exit
status; `TPair` results → `RESULT_KEY` + `RESULT`.

---

## TCustomDictionary members

### Create

```pascal
constructor Create; virtual; overload;
constructor Create(ACapacity: SizeInt); virtual; overload;
constructor Create(ACapacity: SizeInt; const AComparer: IEqualityComparer<TKey>); virtual; overload;
constructor Create(const AComparer: IEqualityComparer<TKey>); overload;
constructor Create(ACollection: TEnumerable<TDictionaryPair>); virtual; overload;
constructor Create(ACollection: TEnumerable<TDictionaryPair>; const AComparer: IEqualityComparer<TKey>); virtual; overload;
```

Creates a dictionary. `ACapacity` pre-sizes the hash table; the collection
overloads copy every pair via `Add` (impl:106–114 — a duplicate raise aborts
the loop); the comparer overloads install a custom key-equality/hash provider.

**kcl:** `TDictionary.new d [ACapacity]` — the capacity argument is accepted
and **ignored** (bash's assoc array sizes itself; API v2 decision).
`Create(ACollection)` → `d.Assign src` (replace content with a copy) and
`d.AddPairs k v [k v …]` (bulk literal pairs, same abort-at-duplicate shape).
Comparer overloads → **wontfix**: a custom equality cannot back a bash
assoc-array lookup; keys compare as exact byte strings.

### Destroy

```pascal
destructor Destroy; override;
```

Calls `Clear` (notifications fire), then frees the Keys/Values collection
objects (impl:128–135).

**kcl:** `d.delete` → destructor `Destroy`: `Clear` (events fire) + storage
teardown.

### Clear

```pascal
procedure Clear; virtual; abstract;   // implemented in TOpenAddressing, impl:515
```

Removes every pair. The storage is released FIRST (`FItems := nil`), then each
old pair is notified `cnRemoved` — callbacks observe an already-empty
dictionary.

**kcl:** `d.Clear` — same order (tests pin `count == 0` during the callbacks).

### Add (pair overload)

```pascal
procedure Add(const APair: TPair<TKey, TValue>); virtual; abstract;   // impl:443
```

Adds a key/value pair; delegates to `Add(Key, Value)`.

**kcl:** folded into `d.Add key value` (a bash "pair" is two arguments).

### ToArray

```pascal
function ToArray: TArray<TDictionaryPair>; virtual; final; overload;
```

Returns all pairs as an array.

**kcl:** `d.ToArrays kVar vVar` — two index-aligned indexed arrays
(`kVar[i]` ↔ `vVar[i]`), lossless for any bash string.

### Count

```pascal
property Count: SizeInt read FItemsLength;
```

Number of stored pairs.

**kcl:** `d.count` — computed from the storage (`${#items[@]}`), cannot drift.

### MaxLoadFactor / LoadFactor / Capacity

```pascal
property MaxLoadFactor: single read FMaxLoadFactor write SetMaxLoadFactor;
property LoadFactor: single read GetLoadFactor;
property Capacity: SizeInt read GetCapacity write SetCapacity;
```

Allocator knobs: growth threshold (`TLinearProbing.DEFAULT_LOAD_FACTOR = 0.75`,
max `1`), current fill ratio, bucket-array size (pow2, min 8; `SetCapacity`
below `Count` raises `EArgumentOutOfRangeException`).

**kcl: wontfix (API v2).** These control a real allocator in FPC; `declare -A`
offers no preallocation or bucket introspection, so emulated values would be
state affecting nothing. FPC's dictionary capacity never mutates data, so no
observable behavior is lost.

### OnKeyNotify / OnValueNotify

```pascal
property OnKeyNotify: TCollectionNotifyEvent<TKey> read FOnKeyNotify write FOnKeyNotify;
property OnValueNotify: TCollectionNotifyEvent<TValue> read FOnValueNotify write FOnValueNotify;
// TCollectionNotifyEvent = procedure(ASender: TObject; constref AItem: T;
//                                    AAction: TCollectionNotification) of object;
```

Change events; `TCollectionNotification = (cnAdded, cnRemoved, cnExtracted)`.
`PairNotify` = `KeyNotify` then `ValueNotify` (impl:40–45); the value-overwrite
path (`SetValue`, impl:54–63) assigns first, then fires `ValueNotify(old,
cnRemoved)` + `ValueNotify(new, cnAdded)` with no key event.

**kcl:** `d.onKeyNotify = funcName` / `d.onValueNotify = funcName`; callback
contract `cb <dict> <item> <added|removed|extracted>`. `KeyNotify`/`ValueNotify`
are public overridable methods (the virtual seam TObjectDictionary hooks).
Event order is ported exactly, including assign-before-notify on overwrite.

---

## TOpenAddressing members (the TDictionary working set)

### Add

```pascal
procedure Add(const AKey: TKey; const AValue: TValue); overload; inline;
```

Inserts a new pair; an existing key raises `EListError` (SDuplicatesNotAllowed,
impl:399) *before* any mutation or notification. Notifies `cnAdded` after the
write (impl:420–431).

**kcl:** `d.Add key value` — duplicate → rc 1, dictionary and events untouched.

### Remove

```pascal
procedure Remove(const AKey: TKey);
```

Removes the pair; a missing key exits silently (impl:492–501). Notifies
`cnRemoved` after the removal (impl:477–490).

**kcl:** `d.Remove key` — absent key → silent rc 0.

### ExtractPair

```pascal
function ExtractPair(const AKey: TKey): TPair<TKey, TValue>;
```

Removes and returns the pair with notification `cnExtracted` (ownership is
handed back — `TObjectDictionary` does NOT free extracted items). A missing
key returns `Default(TPair)` — note the default key equals `''`, so the miss
shape is indistinguishable from extracting the `''`-keyed pair (impl:503–513).

**kcl:** `d.ExtractPair key` — `RESULT_KEY`/`RESULT` on a DIRECT call (a `$()`
capture yields the value but mutates only the subshell copy); miss → both
empty, rc 0. The same `''`-ambiguity exists; disambiguate with `ContainsKey`.

### TrimExcess

```pascal
procedure TrimExcess;
```

`SetCapacity(Count + 1)` — shrinks the bucket array (impl:657).

**kcl: wontfix** — capacity family (see above).

### GetOrAddMutableValue / GetMutableValue / TryGetMutableValue

```pascal
function GetOrAddMutableValue(const AKey: TKey): PValue; inline;
function GetMutableValue(const AKey: TKey): PValue; inline;
function TryGetMutableValue(const AKey: TKey; out APValue: PValue): Boolean;
```

Pointer access to the stored value for in-place mutation.

**kcl: wontfix** — no pointers in bash. The read-with-fallback essence
survives as `d.GetValueDef key default` (kcl convenience, not in FPC).

### TryGetValue

```pascal
function TryGetValue(const AKey: TKey; out AValue: TValue): Boolean;
```

True + the value, or False + `Default(TValue)` (impl:705–716).

**kcl:** `d.TryGetValue key` — rc 0 + `RESULT`, or rc 1 + `RESULT=""`.

### TryAdd

```pascal
function TryAdd(const AKey: TKey; const AValue: TValue): Boolean;
```

Adds only if absent; returns whether it added (impl:718–727). The negative
case is an answer, not an error.

**kcl:** `d.TryAdd key value` — rc 0 added / rc 1 silent.

### AddOrSetValue

```pascal
procedure AddOrSetValue(const AKey: TKey; const AValue: TValue);
```

Upsert (impl:729–740): insert → `cnAdded` pair; overwrite → `SetValue`
semantics (value swap events, key silent).

**kcl:** `d.AddOrSetValue key value`.

### ContainsKey

```pascal
function ContainsKey(const AKey: TKey): Boolean; inline;
```

**kcl:** `d.ContainsKey key` — exit status.

### ContainsValue

```pascal
function ContainsValue(const AValue: TValue): Boolean; overload;
function ContainsValue(const AValue: TValue; const AEqualityComparer: IEqualityComparer<TValue>): Boolean; virtual; overload;
```

Linear scan with the default (or a custom) value comparer (impl:750–774).

**kcl:** `d.ContainsValue value` — O(n), exact string equality. The custom
comparer overload is **wontfix** (comparers not ported).

### Items (default property)

```pascal
property Items[Index: TKey]: TValue read GetItem write SetItem; default;
```

Read: missing key raises `EListError` (impl:640–655). **Write: UPDATE-ONLY —
missing key raises** `EListError` SItemNotFound (impl:662–671). This is where
FPC rtl-generics differs from Delphi, whose `Items[]` write upserts.

**kcl:** `d.GetItem key` (miss → rc 1, `RESULT=""`) / `d.SetItem key value`
(miss → rc 1, nothing inserted). The divergence-from-Delphi is pinned by test.

### Keys / Values

```pascal
property Keys: TKeyCollection read GetKeys;
property Values: TValueCollection read GetValues;
```

Collection views with `Count`, `ToArray` and enumerators. Enumeration order is
unspecified (bucket order, changes on rehash).

**kcl:** `d.Keys` / `d.Values` (one item per line) + `d.KeysToArray var` /
`d.ValuesToArray var` (lossless `ToArray` analogs). Their `.Count` equals
`d.count`. Order is likewise unspecified.

### GetEnumerator / Ptr / GetMemoryLayout

```pascal
function GetEnumerator: TPairEnumerator; reintroduce;
property Ptr: PPointersCollection read GetPointers;
procedure GetMemoryLayout(const AOnGetMemoryLayoutKeyPosition: TOnGetMemoryLayoutKeyPosition);
```

Pair enumerator object (`for pair in dict`), raw-pointer view, and a debug
walk of the physical bucket layout.

**kcl:** `GetEnumerator` → `d.ForEach cb` (`cb key value` per pair; snapshot
semantics — safe under mutation, where the FPC enumerator is undefined).
`Ptr`, `GetMemoryLayout` → **wontfix** (pointers / bucket layout do not exist
in bash).

---

## TDictionary

```pascal
TDictionary<TKey, TValue> = class(TOpenAddressingLP<TKey, TValue>);   // :668
```

The "for normal programmers" specialization: linear probing, default hash
factory. All members above.

**kcl:** `class TDictionary` in `tdictionary.sh` — the whole public surface,
minus the wontfix machinery. The alternative-backend aliases
(`THashMap`/`TFastHashMap`/`TCuckooD*`/`TOpenAddressingQP/DH/LPT…`) are
**wontfix**: bash has exactly one backend, `TDictionary` covers them all.

---

## TObjectDictionary

```pascal
TDictionaryOwnerships = set of (doOwnsKeys, doOwnsValues);            // :596

TObjectDictionary<TKey, TValue> = class(TObjectOpenAddressingLP<TKey, TValue>);  // :669

constructor Create(AOwnerships: TDictionaryOwnerships); overload;
constructor Create(AOwnerships: TDictionaryOwnerships; ACapacity: SizeInt); overload;
```

A dictionary that owns its keys and/or values. The `KeyNotify`/`ValueNotify`
overrides (impl:2389–2405) call `inherited` first, then free the item iff the
ownership flag is set **and the action is `cnRemoved`** — so `Remove`, `Clear`,
`Destroy` and the overwrite path free owned items, while `ExtractPair`
(`cnExtracted`) hands ownership back, and a rejected duplicate `Add` frees
nothing.

**kcl:** `class TObjectDictionary : TDictionary`;
`TObjectDictionary.new od "doOwnsKeys doOwnsValues" [ACapacity]` (tokens
space- or comma-separated, `''` = none, unknown token → rc 1 with no flags
applied; capacity ignored). Owned items must be kklass instance names —
freeing calls `$item.delete`; non-instance strings are skipped silently. The
exact FPC consequence matrix is pinned by tests (013).
