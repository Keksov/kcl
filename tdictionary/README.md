# tdictionary — FPC TDictionary / TObjectDictionary for bash

A bash port of Free Pascal's `Generics.Collections.TDictionary<TKey,TValue>`
(and `TObjectDictionary`) as kklass Pascal-DSL **instantiable** classes.

**Design: a thin wrapper around `declare -A`.** The port keeps the FPC API
surface and its exact observable *data* semantics; the FPC hashing machinery
(open addressing, probe sequences, tombstones, cuckoo maps, hash factories,
equality comparers) and its memory knobs (`Capacity`, `SetCapacity`,
`TrimExcess`, `LoadFactor`, `MaxLoadFactor`) are **not ported** — bash's
associative array *is* the hash table and manages its own storage. Keys and
values are arbitrary bash strings (byte-exact, including the empty string;
NUL is impossible in bash). Keys compare as exact byte strings.

Upstream API reference (per-member Pascal signatures + mapping):
[docs/TDictionary.md](docs/TDictionary.md). Plan and scoping rationale:
[PLAN.md](PLAN.md). Status ledger: `tdictionary_ledger.json`.

## Quickstart

```bash
source kcl/tdictionary/tdictionary.sh

TDictionary.new d            # TDictionary.new d 1000 also works (arg ignored)
d.Add host example.com       # duplicate key -> rc 1, dict unchanged
d.AddOrSetValue port 8080    # upsert
if d.TryGetValue host; then  # direct call: value lands in $RESULT
    echo "host=$RESULT"
fi
echo "pairs: $(d.count)"
d.ForEach my_cb              # my_cb() { echo "key=$1 value=$2"; }
d.Remove host                # absent key -> silent no-op (FPC parity)
d.delete                     # destructor: Clear (events fire) + teardown
```

## API

### Insertion

| Method | Semantics | rc |
|---|---|---|
| `d.Add key value` | insert; **duplicate → error, dict unchanged** (FPC `EListError`) | 0 / 1 |
| `d.TryAdd key value` | insert only if absent; duplicate is a silent negative answer | 0 / 1 |
| `d.AddOrSetValue key value` | upsert | 0 |
| `d.AddPairs k v [k v …]` | bulk `Add`; odd arg count → rc 1, nothing added; a duplicate **aborts at that pair** (earlier stay, later not attempted — FPC `Create(ACollection)` shape) | 0 / 1 |

### Lookup

| Method | Semantics | rc |
|---|---|---|
| `d.GetItem key` | `Items[key]` read; echoes and sets `RESULT`; miss → `RESULT=""` | 0 / 1 |
| `d.SetItem key value` | `Items[key]` write — **UPDATE-ONLY**: missing key → rc 1, nothing inserted. FPC semantics; **Delphi would upsert here** | 0 / 1 |
| `d.TryGetValue key` | `RESULT`=value; miss → `RESULT=""` (FPC `Default(TValue)`) | 0 / 1 |
| `d.GetValueDef key [default]` | value if the key exists (a stored `""` wins!), else the default. *bash convenience, not in FPC* | 0 |
| `d.ContainsKey key` | boolean via exit status | 0 / 1 |
| `d.ContainsValue value` | O(n) scan, exact string equality | 0 / 1 |
| `d.count` | number of pairs (computed from storage — cannot drift) | 0 |

### Removal

| Method | Semantics | rc |
|---|---|---|
| `d.Remove key` | delete; **absent key → silent no-op** (FPC parity) | 0 |
| `d.ExtractPair key` | hit: `RESULT_KEY`/`RESULT` set, pair removed, action `extracted`; miss: `RESULT_KEY=""` `RESULT=""` — **rc 0, not an error** (FPC `Default(TPair)`) | 0 |
| `d.Clear` | remove everything (events fire per pair; callbacks see an already-empty dict) | 0 |
| `d.delete` | destructor `Destroy` = `Clear` (events fire) + storage teardown | 0 |

### Iteration (order is UNSPECIFIED — same as FPC)

| Method | Semantics |
|---|---|
| `d.Keys` / `d.Values` | one item per line (ambiguous for embedded newlines — use the array forms) |
| `d.KeysToArray var` / `d.ValuesToArray var` | fill a named indexed array, **lossless** (newline-safe); the array is reset first |
| `d.ToArrays kVar vVar` | two index-aligned parallel arrays: `kVar[i]` ↔ `vVar[i]`; names must differ |
| `d.ForEach cb` | invoke `cb key value` per pair over a **snapshot**: the callback may freely `Remove`/`Add` — deleted pairs are skipped, additions are not visited in this pass; callback rc ignored |
| `d.Assign src` | replace content with a copy of another TDictionary (`Create(ACollection)` analog); self-assign is a no-op; invalid source → rc 1, dict untouched |

### Events

`d.onKeyNotify = funcName` / `d.onValueNotify = funcName` (empty string = off).
The callback is invoked as **`cb <dict> <item> <added|removed|extracted>`**.
Order is FPC-exact:

| Path | Events |
|---|---|
| insert (`Add`/`TryAdd`/`AddOrSetValue`/`AddPairs`) | key `added`, then value `added` — after the write |
| rejected duplicate `Add` | **nothing** |
| overwrite (`SetItem`/`AddOrSetValue`) | value(old) `removed`, value(new) `added`; the dict already holds the new value; **key silent** |
| `Remove` | key `removed`, value `removed` — after the pair is gone |
| `ExtractPair` | key `extracted`, value `extracted` — never a `removed` |
| `Clear` / `d.delete` | per pair: key `removed`, value `removed` — storage is emptied first |

A dictionary with no hooks pays a single string test per mutation — no
dispatch. A dangling callback name is skipped (mutation unaffected).

### TObjectDictionary — owning dictionary

```bash
TObjectDictionary.new od "doOwnsValues"          # or "doOwnsKeys doOwnsValues"
TDictionary.new payload
od.Add job1 payload      # od now OWNS payload
od.Remove job1           # -> payload.delete (freed)
```

Owned keys/values must be **kklass instance names**; freeing calls
`$item.delete`. Items that do not name a live instance are skipped silently.
Unknown ownership tokens reject the whole set (rc 1, none applied).

| Operation | Owned item |
|---|---|
| `Remove`, `Clear`, `d.delete` | **freed** |
| `ExtractPair` | **not freed** — ownership handed back to the caller |
| overwrite (`SetItem`/`AddOrSetValue`) | the **replaced** value freed; the new one is not |
| rejected duplicate `Add` | nothing freed |

User callbacks fire *before* the free (FPC: `inherited` precedes `.Free`) and
observe the instance still alive.

## Conventions and caveats

- **`func` results**: methods echo the result *and* set `RESULT`. The direct
  call + `$RESULT` form is lossless; `$(…)` strips trailing newlines.
- **`$()` never mutates**: command substitution runs in a subshell, so
  `v=$(d.ExtractPair k)` returns the value but the parent dictionary keeps the
  pair. Mutating calls must be DIRECT calls. (Pinned by tests.)
- **Errors**: FPC exceptions map to `return 1`; a diagnostic is printed only
  under `VERBOSE_KKLASS=debug`. Boolean queries answer via exit status.
- **`SetItem` is update-only** — the documented FPC-vs-Delphi divergence.
- **`ExtractPair` miss vs `''`-key hit** produce the same `('','')` shape —
  exactly as in FPC (`Default(TKey)` is `''`); disambiguate with `ContainsKey`
  beforehand.
- **Reserved names**: do not pass output-variable names starting with `__td_`
  to the `*ToArray`/`ToArrays` methods, and do not touch `${instance}_data`
  (kklass's own property store); pair storage lives in `${instance}_items`.
- **Zero forks** in every method on the direct-call path (`bench.sh` proves it
  with `PATH=''`).

## Out of scope (see PLAN.md §1 for reasons)

Hashing machinery (probe sequences, tombstones, cuckoo variants, hash
factories, custom equality comparers), the capacity family
(`Capacity`/`SetCapacity`/`TrimExcess`/`LoadFactor`/`MaxLoadFactor` — the
constructor's `ACapacity` argument is accepted and ignored), pointer API
(`Ptr`, `*MutableValue`), enumerator objects, `THashMap`/`TFastHashMap`
aliases, `TPair.Create`, NUL bytes in keys/values.

## Tests and benchmark

- `tests/tests.sh` — 130 checks (001–013), green on bash 5.2.37 and 5.3.9;
  FPC-seeded from `packages/rtl-generics/tests/tests.generics.dictionary*.pas`.
  Non-FPC cases are logged in [TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md).
- `bench.sh` — per-op latency, O(1) scaling proof (1k vs 10k pairs),
  zero-fork check, `tlist.Add` reference point.
