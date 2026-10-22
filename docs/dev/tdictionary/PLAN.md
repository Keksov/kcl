# TDictionary → bash port plan (kcl/tdictionary)

**Source of truth:** `C:/projects/KKMindWave/VendorsCore/fpc/sources/main/packages/rtl-generics/src/inc/generics.dictionariesh.inc` (interface, 676 lines) and `inc/generics.dictionaries.inc` (implementation) — FPC rtl-generics (`Generics.Collections`, Maciej Izak / DaThoX). `TDictionary<K,V> = class(TOpenAddressingLP<TKey,TValue>)` (dictionariesh.inc:668).
**Target:** `kcl/tdictionary/tdictionary.sh` — kklass Pascal-DSL **instantiable** classes `TDictionary` and `TObjectDictionary : TDictionary` (model units: `kcl/tlist`, `kcl/tstringlist`).
**Ledger (single source of truth for status):** `kcl/tdictionary/tdictionary_ledger.json`.
**Workflow:** same as dateutils/math — implement per phase, full regression sweep, STOP with a brief review, next phase on explicit "go". Commits gated.

---

## 1. Scoping analysis — what is worth porting to bash

The FPC unit is ~90% *hash-table construction machinery*: it builds dictionaries out of plain
Pascal arrays via open addressing (linear/quadratic/double-hash probing, tombstones) and
deamortized cuckoo hashing, parameterized by hash factories and equality comparers.
**Bash already ships a native hash table** — `declare -A` — implemented in C. Porting the probing
machinery would replicate, in the slowest possible language, what the interpreter already does
faster, and would change no observable semantics. So the port takes the **public API surface and
its exact semantics**, and drops the hashing internals wholesale.

### Ported (full observable semantics)

| FPC | bash | Notes |
|---|---|---|
| `TDictionary<K,V>` public API | class `TDictionary` | K,V = arbitrary bash strings (generics collapse) |
| `Create` / `Create(ACapacity)` | `TDictionary.new d [ACapacity]` | argument accepted for signature compat, **ignored** (§2.5) |
| `Destroy` | `d.delete` → destructor | FPC parity: Destroy calls Clear → notifications fire |
| `Add`, `TryAdd`, `AddOrSetValue` | `d.Add k v` … | duplicate/upsert semantics pinned in §3 |
| `Remove`, `ExtractPair`, `Clear` | `d.Remove k` … | ExtractPair returns pair via RESULT_KEY/RESULT |
| `Items[]` get/set | `d.GetItem k` / `d.SetItem k v` | FPC SetItem is **update-only** (≠ Delphi upsert!) |
| `TryGetValue`, `ContainsKey`, `ContainsValue` | rc + RESULT | ContainsValue O(n) scan, exact string equality |
| `Count` | `d.count` | computed from `${#items[@]}` — cannot drift |
| `Keys`, `Values` collections + `ToArray` | `d.Keys`/`d.Values` (echo lines) + `d.KeysToArray var`/`d.ValuesToArray var`/`d.ToArrays kVar vVar` | lossless nameref forms replace collection objects |
| pair enumerator (`for pair in dict`) | `d.ForEach callback` | callback receives `key value`; snapshot semantics |
| `OnKeyNotify`, `OnValueNotify` | `d.onKeyNotify = cbName` | cb invoked `cb <dict> <item> <added\|removed\|extracted>` |
| `Create(ACollection)` ctor family | `d.Assign srcDict` + `d.AddPairs k v [k v …]` | bash shapes of "construct from pairs" |
| `TObjectDictionary` + `TDictionaryOwnerships` | class `TObjectDictionary : TDictionary` | frees owned **kklass instances** via `.delete` on cnRemoved |

Bash-convenience extras (not in FPC, documented per TEST_COVERAGE_NOTES protocol):
`GetValueDef key default` (TryGetValue sugar), `AddPairs`, `ToArrays`, the `*ToArray` nameref fills.

### NOT ported (wontfix, with reasons)

1. **Hashing machinery** — `THashFactory`/`IEqualityComparer`/`IExtendedEqualityComparer`,
   probe sequences (`TLinearProbing`/`TQuadraticProbing`/`TDoubleHashing`), tombstone variants
   (`TOpenAddressingSH/LPT/QP/DH`), cuckoo maps (`TCuckooD2/D4/D6`, deamortization queue, CDM
   cycle detection), `Rehash`, `GetMemoryLayout`, `TombstonesCount`, `QueueCount`.
   *Reason:* `declare -A` IS the hash table; a bash reimplementation is 10–100× slower with zero
   semantic gain. Custom comparers cannot back an assoc-array lookup at all (they would force
   O(n) scans, defeating the container's purpose). Keys compare as exact byte strings.
2. **Pointer API** — `Ptr` collection, `PKey/PValue` enumerators, `GetMutableValue`,
   `TryGetMutableValue`, `GetOrAddMutableValue`. No pointers in bash; the useful essence of
   GetOrAdd survives as `GetValueDef`/`TryAdd`.
3. **Enumerator objects** (`TPairEnumerator` etc., MoveNext/Current protocol) — replaced by
   `ForEach` + `*ToArray`; an object-per-iteration protocol is pure dispatch overhead in bash.
4. **Alias classes** `THashMap`/`TFastHashMap`/`TObjectHashMap`/… — they select alternative
   backends; bash has exactly one backend, `TDictionary` covers all of them.
5. **`TEmptyRecord`** dictionary-as-set trick — internal, N/A.
6. **`TPair.Create`** record constructor — pairs travel as `RESULT_KEY`/`RESULT` or callback args.
7. **NUL bytes** in keys/values — bash strings cannot hold NUL (language limit, documented).
8. **The capacity family** — `Capacity`, `SetCapacity`, `TrimExcess`, `LoadFactor`,
   `MaxLoadFactor` (owner decision 2026-07-12, "API v2 / thin wrapper"). In FPC these are
   knobs of a *real* allocator (memory + rehash cost). `declare -A` offers no preallocation
   and no bucket introspection, so the emulated numbers would be state that affects nothing —
   parity theater at real cost (per-Add threshold arithmetic, a whole phase of code and
   tests). Unlike tlist's capacity (which truncates data when set below count — observable
   DATA semantics, rightly ported), FPC's dictionary capacity never mutates data. The
   constructor's `ACapacity` argument is accepted and ignored so ported Pascal code
   (`TDictionary.Create(1000)`) keeps working.

---

## 2. Design decisions

### 2.1 Storage: one assoc array per instance, prefixed keys
Pairs live in a per-instance associative array `${__inst__}_items` (assoc, unlike tlist's
indexed array of the same name; matches FPC's `FItems` field), accessed via `declare -n`.
**P0 finding:** the name `${instance}_data` is TAKEN — it is kklass's own per-instance
property store (count/capacity live there as `d_data[count]`); wiping it destroys the
object's fields. **Every key is stored under a one-char prefix**: `items["k$key"]`. Verified
on bash 5.2.37: `a['']=x` → *"bad array subscript"* — the empty string is a valid FPC key, so
raw keys cannot be subscripts. The constant prefix makes every subscript non-empty and
version-proof; iteration strips it with `${k#k}`. Cost: one char per entry, zero forks.

### 2.2 Safe operations for arbitrary keys
Keys may contain `] } * ? " '` spaces and newlines. Pinned idioms (validated by
tests/002_StorageIdioms.sh on 5.2.37 AND 5.3.9 — 34-key torture incl. `''`, `]`, `*`,
newline, `$(echo pwned)`, prefix-collision candidates `k`/`kk`, nameref path, zero-fork):
- **existence:** `[[ -n ${ref["k$key"]+x} ]]` — parameter expansion, single-expansion safe on all target bashes;
- **unset:** `pk="k$key"; unset 'ref[$pk]'` — single-quoted, so `unset` expands the subscript
  exactly once (no double-expansion trap of `unset "ref[$k]"`). The planned scoped
  `assoc_expand_once` dance proved unnecessary: it exists to protect keys that are empty or
  the special subscripts `@`/`*`, and the storage prefix already guarantees `pk` is never any
  of those. Works identically through a nameref.

### 2.3 count, ordering
`count` is a COMPUTED property (`property count read GetCount`) returning `${#items[@]}` —
the prefix scheme stores exactly one entry per pair, so the storage length IS the count and
drift is impossible by construction (no stored mirror to maintain). **Enumeration order is
unspecified** — true in FPC (hash order, changes on rehash) and in bash (`${!ref[@]}`
internal order). Tests compare sorted. No insertion-order bookkeeping: FPC does not offer
it, and it would tax Remove.

### 2.4 Naming, returns, errors (tlist family conventions)
- Methods PascalCase (`Add`, `TryGetValue`, `ExtractPair`…); properties lowercase
  (`count`, `onKeyNotify`, `onValueNotify`).
- `func` methods echo the result AND set `RESULT` (direct call + `$RESULT` preserves trailing
  newlines that `$()` would strip); `ExtractPair` additionally sets `RESULT_KEY`.
- Errors mirror FPC exceptions as `return 1` with a debug message only under
  `VERBOSE_KKLASS=debug` (tlist convention). Boolean queries return via exit status.

### 2.5 Capacity family: DROPPED (API v2, owner decision 2026-07-12)
The original plan emulated FPC's capacity arithmetic (pow2 growth, `Round(size*0.75)-1`
thresholds, TrimExcess quirks) on stored bookkeeping. Dropped after review: those numbers
control a real allocator in FPC, but in bash they would affect nothing — parity theater
with a per-Add cost. The port is a thin wrapper: `declare -A` manages its own storage.
Consequences:
- `capacity`, `SetCapacity`, `TrimExcess`, `LoadFactor`, `MaxLoadFactor` → wontfix (§1);
- `TDictionary.new d [ACapacity]` accepts and ignores the argument (porting compat);
- `count` is computed from the storage (§2.3), so mutation methods maintain NO counters;
- former phase P4 is dropped; `_pow2cap`/`_mulRound` never ship.
Everything remaining is still **Tier A — pure bash, zero forks, no float engine.**

### 2.6 Notifications
`onKeyNotify`/`onValueNotify` hold a bash function name; empty = off (zero overhead beyond one
`[[ -n ]]`). Plumbing copies FPC exactly (impl:40–70): PairNotify = KeyNotify + ValueNotify;
Add → added; Remove/Clear → removed; ExtractPair → extracted; SetItem/AddOrSetValue overwrite →
ValueNotify(old, removed) then ValueNotify(new, added), key not re-notified (SetValue, impl:54);
Destroy → Clear → per-pair removed.

### 2.7 TObjectDictionary
`class TObjectDictionary : TDictionary` — kklass inheritance with `override proc KeyNotify` /
`ValueNotify`, exactly the FPC shape (impl:2389–2405): after `inherited`, if the ownership flag
is set AND the notification is **removed** (never extracted), free the item — in kklass terms,
call `$item.delete` when `$item` names a live kklass instance. Constructor takes ownership
tokens: `TObjectDictionary.new od "doOwnsValues" [capacity]` (or `"doOwnsKeys doOwnsValues"`).
Pinned consequences: `ExtractPair` hands ownership back (no free); `AddOrSetValue` over an
existing key **frees the old value** when doOwnsValues; a failed duplicate `Add` frees nothing.

---

## 3. Pinned FPC semantics (from the implementation source)

| Operation | Found / ok | Missing / duplicate |
|---|---|---|
| `Add k v` (impl:399 InternalDoAdd) | insert, notify added | duplicate → EListError → **rc=1, no mutation** |
| `TryAdd k v` (impl:718) | insert, notify added, rc=0 | rc=1, silent |
| `AddOrSetValue k v` (impl:729) | upsert; overwrite = SetValue notifications | — |
| `Remove k` (impl:492) | delete, notify removed | **silent no-op, rc=0** |
| `ExtractPair k` (impl:503) | RESULT_KEY=k RESULT=v, delete, notify extracted | Default pair: RESULT_KEY="" RESULT="", **rc=0** |
| `GetItem k` (impl:640) | RESULT=v | EListError → rc=1, RESULT="" |
| `SetItem k v` (impl:662) | update + SetValue notifications | EListError → rc=1 (**update-only**, FPC ≠ Delphi) |
| `TryGetValue k` (impl:705) | RESULT=v, rc=0 | RESULT="" (Default), rc=1 |
| `ContainsKey k` (impl:742) | rc=0 | rc=1 |
| `ContainsValue v` (impl:750) | rc=0 (O(n), exact equality) | rc=1 |
| `Clear` (impl:515) | notify removed per pair; count→0 | — |
| `Destroy` (impl:128) | Clear first (notifications fire), then teardown | — |

Constructor: `Create(ACapacity)` — the argument is accepted and ignored (capacity family
dropped, §2.5).

## 4. Parity & test model

- **Everything Tier A** — byte-for-byte comparison against semantics read from the FPC source;
  no tolerance needed anywhere.
- **FPC seeds:** `packages/rtl-generics/tests/tests.generics.dictionary.pas` (TestKeys,
  TestNotificationDelete, TestValueNotification, TestValueNotificationDelete,
  TestKeyValueNotificationSet), `tests.generics.dictionary2.pas` (Add/AddPair/TryAdd/AddOrSet ×
  modify/remove matrix), `tests.generics.stdcollections.pas` — mined per phase.
- **New-coverage protocol:** every case not traceable to an FPC test gets a row in
  `TEST_COVERAGE_NOTES.md` (boundary / bash-convention / representation / cross-check), same as
  dateutils/math.
- **Dual-bash:** suite green on 5.2.37 (primary), functional pass on 5.3.9 (secondary).
  Baseline to protect: kcl 1593 (incl. math 81) + kklass 226 = **1819**; re-measure at P0.

## 5. Phases

| Phase | Content |
|---|---|
| **P0** | Scaffolding: class skeleton + ctor/dtor + count; storage model (prefix, safe-unset idiom) validated with exotic keys on both bashes; tests runner; baseline re-measure |
| **P1** | Core CRUD: Add/TryAdd/AddOrSetValue, GetItem/SetItem/TryGetValue/ContainsKey, Remove/Clear — exact miss/dup semantics |
| **P2** | Removal/query extras: ExtractPair, ContainsValue, GetValueDef, Assign, AddPairs |
| **P3** | Iteration: Keys/Values (echo), KeysToArray/ValuesToArray/ToArrays (nameref), ForEach (snapshot, mutation-safe) |
| **P4** | — dropped (capacity family not ported; API v2 decision, §2.5) |
| **P5** | Notifications: onKeyNotify/onValueNotify + full plumbing (SetValue order, Clear, Destroy) — seeded from tests.generics.dictionary.pas |
| **P6** | TObjectDictionary: ownerships, notify overrides freeing kklass instances (removed-only; extract keeps; overwrite frees old) |
| **P7** | Closeout: README.md, docs/TDictionary.md (upstream FPC reference per kcl docs convention), bench.sh (fork-free, O(1) scaling 1k vs 10k), TEST_COVERAGE_NOTES finalization, full sweep, ledger COMPLETE |

## 6. Known bash traps (carried from the math port + new)

- `${instance}_data` is kklass's OWN per-instance property store — never touch it; pair
  storage is `${instance}_items` (P0 collision finding).
- `}#comment` glued to a closing brace swallows the function end → "unexpected EOF"; always ` } # `.
- Unquoted `(a|b)` regex inside `[[ =~ ]]` parses as conditional grouping → use `local re='…'`.
- assoc `unset` double-expansion → §2.2 idiom only; never `unset "ref[$k]"` with raw keys.
- `$()` strips trailing newlines → RESULT direct-call form is the lossless path; tests cover `$'v\n\n'`.
- Empty assoc subscript is invalid on 5.2 → prefix storage everywhere, no exceptions.
- Hot paths use namerefs directly (tlist pattern); no `$this.X` chains inside loops.

## 7. Deliverables

`tdictionary.sh`, `tests/` (tests.sh + NNN_*.sh), `README.md` (bash API), `docs/TDictionary.md`
(upstream FPC API reference), `TEST_COVERAGE_NOTES.md`, `bench.sh`, `PLAN.md` (this file),
`tdictionary_ledger.json`.
