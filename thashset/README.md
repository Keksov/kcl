# kcl/thashset — THashSet for bash

A bash port of Free Pascal's rtl-generics `THashSet<T>` as a kklass
**instantiable** class. FPC implements its own set as a dictionary with empty
values (`generics.collections.pas:574` —
`TOpenAddressingLP<T, TEmptyRecord>`), so this unit is the
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

> **Status: phase P1 of this unit's own roadmap.** The membership core is real;
> the set algebra is not written yet. See *Not implemented yet* below and
> `PLAN.md` / `thashset_ledger.json` for the schedule.

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
  appears only under `VERBOSE_KKLASS=debug`), and no partial state. A malformed
  **call** — an output-array name that is not a usable identifier — is rc 2.
- **`set -eu` clean**, loadable and re-loadable.
- **No forks** on any member's path.
- **`s.delete` frees everything**, `${s}_items` included.

## API

`on_notify` is a read/write property (the P3 event seam); everything else is a
method — `Count` included, so it is `s.Count` and the number lands in `RESULT`.

| Member | Result | Notes |
|---|---|---|
| `THashSet.new s` / `s.delete` | — | the destructor releases `${s}_items` |
| `s.Count` | `RESULT` = element count | `${#items[@]}`, fork-free |
| `s.Add item` | rc 0 added / **rc 1 duplicate** | silent on the duplicate; fires `added` only on a real insert (FPC `:3002`) |
| `s.Remove item` | rc 0 removed / **rc 1 absent** | silent on the miss; fires `removed` after the element is gone (FPC `:3009`) |
| `s.Contains item` | rc 0 present / rc 1 absent | FPC `:3036` |
| `s.Extract item` | `RESULT` = the element, or `''` | **rc 0 either way** (FPC `:3019` returns `Default(T)` on a miss), so a miss is indistinguishable from extracting the `''` element — call `Contains` first if that matters. A hit removes and fires `extracted` |
| `s.Clear` | — | empties the storage **first**, then notifies each old element `removed` (FPC `:3031`, the tdictionary model) |
| `s.ToArray outArr` | `RESULT` = element count | fills the caller's array by nameref; **call directly**, `$( )` discards the fill. Order is hash order, i.e. unspecified. A reserved, malformed or associative name is **rc 2** with the set untouched |
| `s.ForEach cb` | — | `cb <item>` per element over a **snapshot**, so a callback may mutate the set. A `cb` that is not a function is rc 1 and nothing runs. The callback's status is ignored |
| `s.Assign src` | — | replaces the contents with a copy of another live `THashSet` (or a descendant). The operand's **class** is checked before any mutation (R5), so assigning a `TQueue` or a `TDictionary` is rc 1 with this set intact |

### Output-array names

`ToArray` binds a nameref to the caller's array, so the name is validated
before the binding (`kcl/README.md` §1.7, shared helper `kk._outName`): it must
be a plain identifier, and it must not be `this`, `__inst__`, `__class__`,
`RESULT`, `REPLY`, `IFS`, anything starting with `__kk_`/`__KK_` or **`__ts_`**
(this unit's own local prefix), the receiving instance's own `${s}_data` /
`${s}_class` / `${s}_items`, or an associative array. Any of those is rc 2 with
`RESULT=''` and nothing written.

Per-member upstream reference: FPC `packages/rtl-generics/src/generics.collections.pas`
— `TCustomSet<T>` (:513–566) and `THashSet<T>` (:570–612, impl :2986–3041).

## Not implemented yet

These members exist in the class declaration and answer with a `__ths_pending__:<member>`
marker, so the surface is stable but the behaviour is not there:

| Member | Phase | FPC |
|---|---|---|
| `s.AddRange i1 [i2 …]` | P2 | `:550` — rc 0 iff **all** were newly added (AND-fold, `:2821`) |
| `s.AddRangeFromArray arrName` | P2 | bash extra: the bulk sibling of `AddRange` |
| `s.UnionWith other` | P2 | `:2853` |
| `s.IntersectWith other` | P2 | `:2861` — two-pass, snapshot-safe |
| `s.ExceptWith other` | P2 | `:2878` |
| `s.SymmetricExceptWith other` | P2 | `:2886` |
| `s.Notify item action` | P3 | the virtual event seam; `on_notify` is already threaded at every mutation |

## Divergences from FPC (all tested)

| Topic | FPC | here |
|---|---|---|
| element type | generic `T` | string; `''` is a valid element |
| `Add`/`Remove`/`Contains` | `Boolean` result | the **exit status**, silent on `false` |
| `Extract` miss | `Default(T)` | `RESULT=''`, rc 0 — the same ambiguity, made explicit |
| iteration order | hash order | hash order (bash associative order) — unspecified, do not depend on it |
| `Capacity` / `TrimExcess` | present | not ported: a bash associative array has no capacity to reserve |
| `TObjectHashSet` | does not exist in FPC | — |

## Tests

`bash kcl/thashset/tests/tests.sh` — on bash 5.2.37 and 5.3.9.
`001_Skeleton.sh` pins the class surface and the pending markers,
`002_MembershipCore.sh` the P1 behaviour including the exotic-element torture,
`003_Contract.sh` the kcl contract (`set -eu`, value round-trip, lifecycle,
output-name validation) and `004_ReviewP2.sh` the 2026-09-06 review
regressions (G2-01 single-quoted `unset`, G2-02 output names, G2-04 `Assign`
class check, G2-05 `ForEach` callback check).
