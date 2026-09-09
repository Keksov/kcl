# kcl/thashset — THashSet for bash

A bash port of Free Pascal's rtl-generics `THashSet<T>` as a kklass
**instantiable** class. FPC implements its own set as a dictionary with empty
values (`generics.collections.pas:535` at the release_3_2_2 tag —
`FInternalDictionary: TOpenAddressingLP<T, TEmptyRecord>`), so this unit is the
[`tdictionary`](../tdictionary/README.md) storage layer with the value
dimension removed. Elements are **strings**, and every string is a valid
element, the empty one included.

```bash
source kcl/thashset/thashset.sh

THashSet.new s
s.Add alpha            # rc 0 — newly added
s.Add alpha            # rc 1 — already present (an ANSWER, not an error)
s.Contains alpha       # rc 0
s.Remove beta          # rc 1 — absent
s.Count                # RESULT=1  (a func: direct call prints nothing)

declare -a items
s.ToArray items        # RESULT = number of elements; call DIRECTLY, not in $( )
s.delete               # destructor: frees the storage array too
```

> **Status: COMPLETE (P0–P4).** Every declared member has a real body — the
> membership core, the set algebra and the event seam — and the suite is
> **149 checks, green on bash 5.2.37 and 5.3.9**. Upstream API reference:
> [docs/THashSet.md](docs/THashSet.md). What the tests pin, case by case:
> [TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md). Numbers: `bench.sh`
> (summarised under *Performance* below). History: `PLAN.md` /
> `thashset_ledger.json`.

## Contract

This unit follows the [kcl contract](../README.md#1-the-kcl-contract):

- **Boolean members answer with their exit status**, and a `false` answer is
  **silent** — `Add` on a duplicate, `Remove` on an absent element and
  `Contains` on a miss are rc 1 with nothing printed and nothing logged. This
  is the loud difference from `TDictionary`, whose `Add` treats a duplicate as
  an error. Under `set -e` call them from an `if`, a `&&`/`||` or a `!`.
- **Values come back in `RESULT`.** A direct call prints nothing; `$(s.Extract
  x)` prints the value exactly once but forks and throws the removal away.
  Elements are data — `-e`, `-n`, embedded newlines, backslashes, `$( )` and
  bracket characters all round-trip byte-exact.
- **Errors are `rc 1` and nothing else** — no stdout, no stderr (a diagnostic
  appears only under `VERBOSE_KKLASS=debug`), and no partial state: an operand
  that is not a live `THashSet` is refused *before* anything is written, so the
  set is left byte-identical. A malformed **call** — an output- or input-array
  name that is not a usable identifier, a target of the wrong kind, or an
  `onNotify` argument that is not a function — is rc 2.
- **`set -eu` clean**, loadable and re-loadable.
- **No forks** on any member's path.
- **`s.delete` frees everything**, `${s}_items` included — and, when a listener
  is attached, notifies `removed` for every element first (FPC `:2554`).

## API

`on_notify` and `_notifyHook` are read/write properties (the event seam);
everything else is a method — `Count` included, so it is `s.Count` and the
number lands in `RESULT`.

| Member | Result | Notes |
|---|---|---|
| `THashSet.new s` / `s.delete` | — | the destructor releases `${s}_items` |
| `s.Count` | `RESULT` = element count | `${#items[@]}`, fork-free |
| `s.Add item` | rc 0 added / **rc 1 duplicate** | silent on the duplicate; fires `added` only on a real insert (FPC `:2559`) |
| `s.Remove item` | rc 0 removed / **rc 1 absent** | silent on the miss; fires `removed` after the element is gone (FPC `:2566`) |
| `s.Contains item` | rc 0 present / rc 1 absent | FPC `:2593` |
| `s.Extract item` | `RESULT` = the element, or `''` | **rc 0 either way** (FPC `:2576` returns `Default(T)` on a miss), so a miss is indistinguishable from extracting the `''` element — call `Contains` first if that matters. A hit removes and fires `extracted` |
| `s.Clear` | — | empties the storage **first**, then notifies each old element `removed` (FPC `:2588`, the tdictionary model) |
| `s.ToArray outArr` | `RESULT` = element count | fills the caller's array by nameref; **call directly**, `$( )` discards the fill. Order is hash order, i.e. unspecified. A reserved, malformed or associative name is **rc 2** with the set untouched |
| `s.ForEach cb` | — | `cb <item>` per element over a **snapshot**, so a callback may mutate the set. A `cb` that is not a function is rc 1 and nothing runs. The callback's status is ignored |
| `s.Assign src` | — | replaces the contents with a copy of another live `THashSet` (or a descendant). The operand's **class** is checked before any mutation (R5), so assigning a `TQueue` or a `TDictionary` is rc 1 with this set intact |
| `s.AddRange i1 [i2 …]` | rc 0 iff **every** item was newly added | the FPC AND-fold (`:2379`: `Result := True; for i in AValues do Result := Add(i) and Result`). Add runs for every item, so the ones that are new land whatever the answer is. **Zero arguments is rc 0** (an empty `array of T`), and a duplicate *inside* the argument list makes it rc 1. Like `Add`, rc 1 is a silent answer |
| `s.AddRangeFromArray arrName` | same Boolean as `AddRange` | bash extra: the bulk sibling, over the elements of a caller **indexed** array (holes in a sparse array are not elements; an empty array is rc 0). The name is validated before the nameref is bound, and a reserved/malformed name, an associative array, a scalar or an unset variable is **rc 2** with nothing added |
| `s.UnionWith other` | — | adds every element of `other` (`:2417`). Duplicates are skipped silently, so only genuinely new elements fire `added`. `a.UnionWith a` is a no-op |
| `s.IntersectWith other` | — | keeps only what `other` also holds (`:2425` — two-pass: collect this set's non-members of `other`, then remove them, so nothing is deleted mid-walk). `a.IntersectWith a` is a defined no-op |
| `s.ExceptWith other` | — | removes every element of `other` (`:2442`); misses are silent. **`a.ExceptWith a` empties the set** |
| `s.SymmetricExceptWith other` | — | keeps what is in exactly one of the two sets (`:2450` — two-pass over `other`: an element this set has is marked, one it lacks is added; then the marked ones are removed). **`a.SymmetricExceptWith a` empties the set** |
| `s.on_notify` | the callback name, `''` = off | stored property: `s.on_notify = "cb"` attaches, `s.on_notify = ""` detaches, `$(s.on_notify)` reads back. This is what the gate tests |
| `s.onNotify cbName` | — | the validating setter for the same slot: `''` detaches (rc 0), a name that is not a function is **rc 2** + a debug line with the **current hook left untouched**, otherwise rc 0. FPC's `SetOnNotify` (`:2530`) cannot validate — a Pascal method pointer either compiles or does not |
| `s.Notify item action` | — | the **virtual** seam. Fires `cb <inst> <item> <action>` when `on_notify` names a function; always rc 0. Override it in a descendant instead of hooking a callback |
| `s._notifyHook` | `''` = only a user callback listens | set it non-empty in a descendant's constructor when that descendant **overrides `Notify`**, so events are dispatched with no user callback attached (the `TObjectDictionary` pattern). Nothing in this unit arms it — FPC declares no set subclass |

The four algebra members are **procedures** in FPC and carry no Boolean here
either: rc 0 on success, and **rc 1** when the operand is not a live `THashSet`
— checked by class before anything is touched, so a rejected operand leaves the
set byte-identical. They snapshot the operand's keys before mutating this set,
which is what makes the self-operation cases above defined rather than a walk
over a table that is changing underneath. Iteration order is hash order, so the
order in which elements are added or removed — and therefore the order of the
events — is unspecified.

### Output-array names

`ToArray` binds a nameref to the caller's array, so the name is validated
before the binding (`kcl/README.md` §1.7, shared helper `kk._outName`): it must
be a plain identifier, and it must not be `this`, `__inst__`, `__class__`,
`RESULT`, `REPLY`, `IFS`, anything starting with `__kk_`/`__KK_` or **`__ts_`**
(this unit's own local prefix), the receiving instance's own `${s}_data` /
`${s}_class` / `${s}_items`, or an associative array. Any of those is rc 2 with
`RESULT=''` and nothing written.

Per-member upstream reference: FPC `packages/rtl-generics/src/generics.collections.pas`
at the **release_3_2_2** tag — `TCustomSet<T>` (declared :474–527, the set
algebra :2379–2467) and `THashSet<T>` (declared :531–574, impl :2500–2601).
The `:3002`-style numbers this file carried before 2026-09-09 came from a
different revision: identical code, different line numbers. The full
per-member transcription lives in [docs/THashSet.md](docs/THashSet.md).

## Ordered iteration

A hash set has no order, and FPC's answer — `TSortedSet` / `TSortedHashSet`
over an AVL tree (`:839` / `:883`) — is **not ported**: a balanced tree buys
nothing over bash's native hash. Sort at the boundary instead, by composing
`ToArray` with [`tarray`](../tarray/README.md)'s `TArray.sort`:

```bash
source kcl/thashset/thashset.sh
source kcl/tarray/tarray.sh

THashSet.new fruit
fruit.AddRange pear apple fig banana cherry || :

declare -a ordered=()
fruit.ToArray ordered          # RESULT = 5; the fill itself is hash order
TArray.sort ordered            # byte order, in place, fork-free
printf '%s\n' "${ordered[@]}"
fruit.delete
```

```
apple
banana
cherry
fig
pear
```

`TArray.sort` also takes `-n` for numeric order or the name of a comparator
function, so any order you can express is one call away; the set itself stays
unordered. `AddRange` is called with `|| :` because its rc is the AND-fold
answer, not an error — under `set -e` an unguarded duplicate would stop the
script. The example is executed end to end by `tests/003_Contract.sh`, so it
cannot drift from the two units.

## THashSet vs TDictionary — the members that differ

The two units share a storage layer and will be used side by side, so the
places where the same verb means something different are worth having in one
table. `d` is a [`TDictionary`](../tdictionary/README.md), `s` a `THashSet`.

| Topic | `TDictionary` | `THashSet` |
|---|---|---|
| add, new | `d.Add k v` → rc 0 | `s.Add x` → rc 0 |
| add, **duplicate** | rc 1 — an **error** (FPC raises `EListError`), with a `VERBOSE_KKLASS=debug` line; `d.TryAdd` is the silent variant | rc 1 — an **answer** (FPC returns `False`), always silent, never logged. There is no `TryAdd`: `Add` already is one |
| remove, hit | `d.Remove k` → rc 0 | `s.Remove x` → rc 0 |
| remove, **miss** | **rc 0** — a silent no-op (FPC `procedure Remove`) | **rc 1** — the Boolean answer (FPC `function Remove: Boolean`), silent |
| extract | `d.ExtractPair k` → `RESULT_KEY` + `RESULT`, action `extracted` | `s.Extract x` → `RESULT`, action `extracted` |
| extract, **miss** | rc 0, `RESULT_KEY=''` `RESULT=''` (`Default(TPair)`) | rc 0, `RESULT=''` (`Default(T)`) — the same ambiguity with `''`, the same cure: ask `Contains` first |
| membership test | `d.ContainsKey k` (and `d.ContainsValue v`, an O(n) scan) | `s.Contains x` — one member, O(1); a set has no second dimension to scan |
| read a value | `d.GetItem k` / `d.TryGetValue k` / `d.GetValueDef k def` | — there is nothing to read: membership *is* the value |
| count | `d.count` (a **property**) | `s.Count` (a **method**, `RESULT`) — both computed from the storage |
| clear | `d.Clear` — storage emptied first, then one event per old pair | `s.Clear` — identical model (S4), one `removed` per old element |
| bulk fill | `d.AddPairs k v [k v …]` — a duplicate **aborts at that pair** | `s.AddRange i1 [i2 …]` — the FPC AND-fold: every item is attempted, rc 0 iff all were new. Plus `s.AddRangeFromArray arrName` |
| event hooks | **two**: `d.onKeyNotify`, `d.onValueNotify` | **one**: `s.on_notify` (+ the `s.onNotify` setter) |
| event callback | `cb <dict> <item> <added\|removed\|extracted>` — fired once for the key and once for the value | `cb <set> <item> <added\|removed\|extracted>` — one event per element |
| event on insert | key `added`, then value `added` | one `added` |
| event on overwrite | value(old) `removed` + value(new) `added`, key silent | — there is no overwrite; a duplicate `Add` fires **nothing** |
| iteration | `d.ForEach cb` → `cb key value`; `d.Keys`/`d.Values`; `d.KeysToArray`/`d.ValuesToArray`/`d.ToArrays` | `s.ForEach cb` → `cb item`; `s.ToArray arr` |
| copy | `d.Assign src` — replaces the contents, source class-checked | `s.Assign src` — identical, and a `TDictionary` is refused (R5) |
| set algebra | — | `s.UnionWith` / `IntersectWith` / `ExceptWith` / `SymmetricExceptWith`, the reason this unit exists |
| ownership subclass | `TObjectDictionary` (owns keys and/or values) | none — FPC declares no `TObjectHashSet`. `_notifyHook` is the extension point |
| capacity | ignored ctor argument (`TDictionary.new d 1000`) | not accepted at all |

Both units store one `declare -A` per instance with the same `k`-prefixed
subscript idioms, so an exotic element is exactly as safe here as an exotic key
there.

## Events

```bash
THashSet.new s
watch() { printf 'set %s: %s %s\n' "$1" "$3" "$2"; }   # cb <inst> <item> <action>
s.onNotify watch          # or the house spelling:  s.on_notify = "watch"

s.Add alpha               # set s: added alpha
s.Add alpha               # (nothing — a duplicate is not a mutation)
s.Add beta                # set s: added beta
s.Remove alpha            # set s: removed alpha
s.delete                  # set s: removed beta — one per surviving element
```

The actions are `added`, `removed` and `extracted` — FPC's `cnAdded` /
`cnRemoved` / `cnExtracted`. In FPC a set has no `Notify` of its own: the
property `TCustomSet.OnNotify` (`:526`) is implemented by re-routing the
internal dictionary's `OnKeyNotify` through a private forwarder that calls
`FOnNotify(Self, AItem, AAction)` (`SetOnNotify :2530`, `InternalDictionaryNotify
:2500`). Two consequences are ported literally: the **sender is the set**, and
with no callback assigned nothing is dispatched at all.

| Path | Events |
|---|---|
| `Add` | one `added` — only on a real insert (a duplicate is silent, S1) |
| `Remove` / `Extract` | one `removed` / one `extracted`, **after** the element is gone; a miss is silent (S2, S6) |
| `Clear` | the storage is emptied **first**, then one `removed` per old element — a callback already sees `Count` 0 (S4). Clearing an empty set is silent |
| `s.delete` | `Destroy` clears first, so one `removed` per element (S5; FPC `:2554` frees the internal dictionary) |
| `Assign` | every `removed` (the old contents) **before** every `added` (the new) |
| `AddRange` / `AddRangeFromArray` | one `added` per genuinely new item, in argument order |
| `UnionWith` | `added` for the operand's elements this set lacked |
| `IntersectWith` | `removed` for this set's elements the operand lacks |
| `ExceptWith` | `removed` for the operand's elements this set held |
| `SymmetricExceptWith` | `added` for the operand-only elements (pass 1), then `removed` for the common ones (pass 2) — that phase order is deterministic |

Rules the tests pin (`tests/006_Events.sh`):

- **Events fire after the mutation.** A callback observes the new state:
  `Contains` on the element of a `removed` event is false, and `Count` during
  `Clear` is 0.
- **A callback may mutate the set.** Every loop walks a snapshot, so the set
  stays consistent (`Count` == storage == `ToArray`) whatever the callback
  does, and the callback's own mutations are delivered as further events —
  events are **re-entrant**. Terminating that recursion is the callback's job:
  one that adds on `added` must stop itself.
- **The callback's exit status is ignored.** A Pascal event is a `procedure`;
  a callback that returns 1 does not change the member's rc and does not abort
  a `set -e` caller.
- **A dangling name is a no-op**, not a crash: one `kk.debug` line per event
  (visible only under `VERBOSE_KKLASS=debug`) and the operation proceeds. The
  name is resolved at fire time, so it may be assigned before the function
  exists.
- **Order within a hash-order path is unspecified.** Only the per-member and
  per-phase orders above are guaranteed.
- **Cost with no listener** is one `[[ ]]` per mutation and no dispatch. 1000
  `Add` calls, measured by `bench.sh` on 2026-09-09: 235 ms unhooked against
  624 ms with a do-nothing listener on bash 5.2.37 (2.6×), 281 ms against
  651 ms on 5.3.9 (2.3×). The delta is one virtual `Notify` dispatch plus the
  callback per element — see *Performance*.

To receive events without a user callback — the reason `_notifyHook` exists —
override the seam in a descendant and arm the hook in its constructor:

```bash
class TAuditSet : THashSet
    public
        constructor   Create
        override proc Notify
end
TAuditSet.Create() { inherited; _notifyHook=1; }
TAuditSet.Notify() { inherited Notify "$@"; AUDIT+=("$1:$2"); }
build TAuditSet
```

## Performance

`bash kcl/thashset/bench.sh` — deterministic sizes, no `$RANDOM`, timed with
`TStopwatch.getTimeStamp` (the shared fork-free µs clock). Measured
**2026-09-09** on Windows 11 / MSYS2:

| Measurement | bash 5.2.37 | bash 5.3.9 |
|---|---|---|
| `Add`, n=1000 | 249.1 µs/op | 239.0 µs/op |
| `Add`, n=5000 | 237.9 µs/op | 235.6 µs/op |
| `Contains` hit, n=1000 / n=5000 | 198.7 / 195.3 µs/op | 203.9 / 204.0 µs/op |
| `Contains` miss, n=1000 / n=5000 | 208.6 / 200.7 µs/op | 206.4 / 204.9 µs/op |
| `Remove`, n=1000 / n=5000 | 258.2 / 229.7 µs/op | 234.4 / 230.0 µs/op |
| **baseline** — one 1k `Add` loop | 219 ms | 233 ms |
| `UnionWith` 1k into a disjoint 1k | 281 ms — **1.2×** | 269 ms — **1.1×** |
| `IntersectWith` 1k × 1k, 50% overlap | 146 ms — **0.6×** | 139 ms — **0.5×** |
| `ExceptWith` 1k × 1k, 50% overlap | 261 ms — **1.1×** | 274 ms — **1.1×** |
| `SymmetricExceptWith` 1k × 1k, 50% | 513 ms — **2.3×** | 536 ms — **2.2×** |
| `Contains` @ 100 vs @ 10 000 elements | 195.8 vs 193.8 µs/op — **0.9×** | 242.1 vs 244.0 µs/op — **1.0×** |
| 1k `Add`, unhooked vs hooked | 235 → 624 ms — **2.6×** | 281 → 651 ms — **2.3×** |

Reading the table:

- **Per-op cost is the kklass instance dispatch**, not the data structure:
  every membership member lands in the same 190–260 µs band, and the band does
  not move between n=1000 and n=5000.
- **The algebra gate is 3× the 1k-`Add` baseline** (`PLAN.md` §5, asserted by
  `tests/005_SetAlgebra.sh` §J). All four operations pass on both bashes; the
  worst is `SymmetricExceptWith` at 2.3×, which is exactly what FPC's two-pass
  algorithm costs — a `Contains` plus an `Add` **or** a deferred `Remove` for
  every element of the operand.
- **`Contains` is flat** — 0.9×/1.0× per op against a set **100× larger**.
  "Flat" here means a ratio below 2.0; a linear scan would show ~100×.
  `declare -A` is a real hash table and the port adds no scan of its own.
- **The event gate costs nothing when nobody listens**: the unhooked loop is
  indistinguishable from the P2/P3 baselines; attaching a do-nothing callback
  costs 2.3–2.6× — one virtual dispatch plus the callback, per element.
- **Zero forks**: `$BASHPID` is unchanged across a sequence of all 17 methods
  plus `new`/`delete`, and a full membership-plus-algebra sequence still
  produces the right answers with `PATH=''`.

## Divergences from FPC (all tested)

| Topic | FPC | here |
|---|---|---|
| element type | generic `T` | string; `''` is a valid element |
| `Add`/`Remove`/`Contains` | `Boolean` result | the **exit status**, silent on `false` |
| `AddRange` | four overloads: `array of T`, `IEnumerable<T>`, `TEnumerable<T>`, `TEnumerableWithPointers<T>` (`:2379`–`:2414`) | one **varargs** form; the set-as-source overloads are `UnionWith` (membership) or `AddRange` over `ToArray` output (Boolean). `AddRangeFromArray` is the bash-only bulk sibling |
| `Extract` miss | `Default(T)` | `RESULT=''`, rc 0 — the same ambiguity, made explicit |
| algebra operand | any `TCustomSet<T>`, and passing something else does not compile | checked at run time by class: rc 1 + `VERBOSE_KKLASS=debug` diagnostic, set untouched |
| `a.ExceptWith a` | walks the argument's live table while removing from it | the operand's keys are snapshot first, so the drain is **defined**: the set ends empty |
| iteration order | hash order | hash order (bash associative order) — unspecified, do not depend on it |
| `Capacity` / `TrimExcess` | present | not ported: a bash associative array has no capacity to reserve |
| `TObjectHashSet` | does not exist in FPC | — |
| the event seam | no virtual `Notify`: `OnNotify` is a property over `Get/SetOnNotify` (`:495`/`:496`) that re-routes the internal dictionary's `OnKeyNotify` | a **public virtual `Notify`** (the house pattern of `tqueuestack`/`tdictionary`) plus `_notifyHook`, so a descendant can receive events without a user callback |
| reading `OnNotify` back | `GetOnNotify` (`:2525`) returns `FInternalDictionary.OnKeyNotify` — the private forwarder, **not** what the caller assigned | `$(s.on_notify)` returns the name that was set |
| assigning a bad handler | will not compile | `s.onNotify bogus` is rc 2 with the current hook kept; a name that stops resolving later is a debug line and a no-op at fire time |

## Tests

`bash kcl/thashset/tests/tests.sh` — **149 checks**, green on bash 5.2.37 and
on 5.3.9. Every case is indexed in
[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md).

| File | Cases | What it pins |
|---|---|---|
| `001_Skeleton.sh` | 10 | the ctor core, computed `Count`, the reduced storage torture, the event surface, and that **no** member answers with a `__ths_pending__` sentinel any more |
| `002_MembershipCore.sh` | 17 | the membership lifecycle, the Boolean-rc contract, `''` as an element, the exotic-element torture through `Remove`/`Extract`, `ForEach`/`Clear`/`Assign` |
| `003_Contract.sh` | 11 | the kcl contract (`set -eu` load and re-load, source integrity, value round-trip, teardown, error path under `set -e`) plus the README's sorted-iteration example, run end to end |
| `004_ReviewP2.sh` | 11 | the 2026-09-06 review regressions: G2-01 single-quoted `unset`, G2-02 output names, G2-04 `Assign` class check, G2-05 `ForEach` callback check |
| `005_SetAlgebra.sh` | 45 | the FPC `Test_Set_General` truth table case for case, the four operations over eight operand shapes with the operand asserted untouched, the self-operation edges, exotic elements through every path, both `AddRange` forms, operand and input-name validation, and the 3× relative performance gate |
| `006_Events.sh` | 55 | the FPC `Test_TCustomSet_Notification` oracle (`tests.generics.sets.pas :261–338`) case for case, the per-member sequences (S1/S2/S4/S5/S6/S9), the algebra ops as event multisets, the callback signature byte-exact over twelve exotic elements, mutating and re-entrant callbacks, the dangling-name and ignored-status edges, the `onNotify` setter, the `_notifyHook` seam through a subclass that overrides `Notify`, and the hook-less cost |

Per-member upstream reference for the events: `THashSet<T>.SetOnNotify :2530`,
`InternalDictionaryNotify :2500`, `GetOnNotify :2525`, `Destroy :2554`, and
`TCustomSet<T>.OnNotify :526`.
