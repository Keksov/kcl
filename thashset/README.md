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

> **Status: phase P2 of this unit's own roadmap.** The membership core and the
> set algebra are real; the event seam (`Notify` / `on_notify`) is still a stub.
> See *Not implemented yet* below and `PLAN.md` / `thashset_ledger.json` for the
> schedule.

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
  name that is not a usable identifier, or a target of the wrong kind — is rc 2.
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

The four algebra members are **procedures** in FPC and carry no Boolean here
either: rc 0 on success, and **rc 1** when the operand is not a live `THashSet`
— checked by class before anything is touched, so a rejected operand leaves the
set byte-identical. They snapshot the operand's keys before mutating this set,
which is what makes the self-operation cases above defined rather than a walk
over a table that is changing underneath. Iteration order is hash order, so the
order in which elements are added or removed (and, from P3, the order of the
events) is unspecified.

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
algebra :2379–2467) and `THashSet<T>` (declared :531–572, impl :2540–2600).
The `:3002`-style numbers this file carried before 2026-09-09 came from a
different revision: identical code, different line numbers.

## Not implemented yet

This member exists in the class declaration and answers with a
`__ths_pending__:Notify` marker, so the surface is stable but the behaviour is
not there:

| Member | Phase | FPC |
|---|---|---|
| `s.Notify item action` | P3 | the virtual event seam; `on_notify` is already threaded at every mutation, the algebra members included |

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

## Tests

`bash kcl/thashset/tests/tests.sh` — on bash 5.2.37 and 5.3.9.
`001_Skeleton.sh` pins the class surface and the pending markers,
`002_MembershipCore.sh` the P1 behaviour including the exotic-element torture,
`003_Contract.sh` the kcl contract (`set -eu`, value round-trip, lifecycle,
output-name validation), `004_ReviewP2.sh` the 2026-09-06 review
regressions (G2-01 single-quoted `unset`, G2-02 output names, G2-04 `Assign`
class check, G2-05 `ForEach` callback check) and `005_SetAlgebra.sh` the P2
algebra: the FPC `Test_Set_General` truth table ported case for case, the four
operations over eight operand shapes with the operand asserted untouched, the
self-operation edges, exotic elements through every path, both `AddRange`
forms, operand and input-name validation, and the relative performance gate.
