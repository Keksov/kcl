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

> **Status: phase P3 of this unit's own roadmap.** Every declared member has a
> real body — the membership core, the set algebra and the event seam. What is
> left is P4: `bench.sh`, `docs/THashSet.md`, the TDictionary-vs-THashSet
> comparison box and the closeout. See `PLAN.md` / `thashset_ledger.json`.

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
algebra :2379–2467) and `THashSet<T>` (declared :531–574, impl :2500–2601).
The `:3002`-style numbers this file carried before 2026-09-09 came from a
different revision: identical code, different line numbers.

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
- **Cost with no listener** is one `[[ ]]` per mutation and no dispatch:
  1000 `Add` calls take 220 ms on bash 5.2.37 (189 ms on 5.3.9) unhooked
  against 566 ms (495 ms) with a do-nothing listener attached.

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
`006_Events.sh` is the P3 event seam: the FPC
`Test_TCustomSet_Notification` oracle (`tests.generics.sets.pas :261–338`)
ported case for case, the per-member sequences (S1/S2/S4/S5/S6), the algebra
ops compared as event multisets against the P2 truth tables, the callback
signature byte-exact over twelve exotic elements, mutating and re-entrant
callbacks, the dangling name and ignored-status edges, the `onNotify` setter,
the `_notifyHook` seam through a subclass that overrides `Notify`, and the
hook-less cost.

Per-member upstream reference for the events: `THashSet<T>.SetOnNotify :2530`,
`InternalDictionaryNotify :2500`, `GetOnNotify :2525`, `Destroy :2554`, and
`TCustomSet<T>.OnNotify :526`.
