# TObjectList → bash port plan (kcl/tobjectlist)

**Origin:** owner-approved side-unit (2026-07-13, collection-hierarchy discussion) —
the OWNING container: the "non-owning vs owning" axis is the genuinely valuable
distinction in bash (elements as kklass-instance HANDLES whose lifecycle the list
manages), unlike the thin "list of strings vs list of strings" one.
**Source of truth:** FPC `packages/fcl-base/src/contnrs.pp` — `TObjectList = class(TList)`
(:82–102; impl: Notify frees on lnDeleted :~1450, SetItem via Put, Extract = remove
without free). **FPC fpcunit seed EXISTS (verified):**
`packages/fcl-base/tests/utcobjectlist.pp` — 9 tests (Create/Add/Extract/Remove/
IndexOf/FindInstanceOf/Insert/FirstLast/OwnsObjects) = the parity oracle.
**Target:** `kcl/tobjectlist/tobjectlist.sh` — kklass class `TObjectList : TList`.
**Ledger:** `kcl/tobjectlist/tobjectlist_ledger.json`.
**Workflow:** phase → dual-bash tests → master sweep → STOP → "go"; commits gated.
**Conventions:** as `kcl/tdictionary/PLAN.md` §2.2–2.4/§6.

---

## 1. Model

An "object" is a **kklass instance handle** (the instance name string). "Free" is
`$handle.delete`. The list stores handles like any TList stores strings; ownership
means removal paths ALSO free the instance.

FPC routes ownership through ONE seam — `Notify(Ptr, lnDeleted)`. Our bash TList
has no notification seam, so TObjectList instead **overrides each removal path**
and composes via kklass `inherited`:

```
TObjectList.Delete()  { <free victim if owns>; inherited Delete "$@"; }
```

### Probe-pinned mechanics (P0, both bashes 5.2.37 + 5.3.9)

| # | Fact | Consequence |
|---|---|---|
| M1 | Plain parent bodies (`TList.Delete`) are UNSET by `build` | can't call parent as a plain fn |
| M2 | **`inherited MethodName args` works in ANY method body** (kk.decl._rewrite_inherited → `$this.parent`) — verified for ctor, Delete, Clear | free-then-`inherited` composition; zero duplication |
| M3 | Parent ctor does NOT auto-chain; `inherited` in ctor chains it | ctor MUST start with `inherited` |
| M4 | Child destructor works when parent has none; dynamic scope gives it `$count` + items | dtor frees owned items |
| M5 | Per-instance dispatcher fn `<handle>.delete` exists while alive, GONE after delete | **liveness guard** `declare -F "$h.delete"` — makes double-free and non-instance strings a safe no-op |
| M6 | `"$var".delete` dispatches fine; ctor token args arrive as `$1` | handles callable from array slots; `Create [false]` token works |

## 2. Design

- **`_free` helper** (plain fn): `[[ -n "$1" ]] && declare -F "$1.delete" >/dev/null && "$1".delete; return 0`.
  Freeing a non-instance string or an already-freed handle is a **silent no-op**
  (bash-side softening: FPC `TObject(garbage).Free` would crash, `nil.Free` is safe;
  our guard generalizes the nil case — documented).
- **`owns_objects` var** (FPC `OwnsObjects` property): plain kklass var → readable/
  writable (`L.owns_objects`, `L.owns_objects = false`) like TStringList's flags.
  **Default TRUE** (FPC parameterless Create). `Create [true|false]` token mirrors
  FPC `Create(FreeObjects: Boolean)`; unknown token → rc 1 (list still valid,
  owns=true), message under VERBOSE_KKLASS=debug (house token convention).
- **Ownership on removal paths only** (FPC Notify fires lnDeleted on): `Delete`,
  `Clear`, `Remove`, `Put` (replacement frees the OLD item unless same handle —
  contnrs SetItem/TList.Put semantics), destructor. NOT on Add/Insert/Extract/
  Exchange/Move/Sort (no lnDeleted there).
- **`Extract item`** (new member; FPC :93): remove WITHOUT freeing → RESULT=item,
  rc 0; miss → RESULT="", rc 1. Body finds the index then calls `inherited Delete`
  — which resolves PAST our own freeing override straight to TList.Delete (M2),
  exactly lnExtracted semantics. (FPC TList.Extract exists too; adding it to tlist
  is out of scope here.)
- **Bounds discipline in overrides:** validate index BEFORE freeing (an invalid
  index must not free anything), then `inherited` (which enforces/errors as TList
  always did — error semantics unchanged).
- **BatchDelete** (bash extra in TList, a removal path): override to free the range
  first — else an owning list would leak through it. BatchInsert needs nothing.
- **FindInstanceOf:** P1-investigate — kklass instances may know their class name;
  if a cheap public mapping exists, implement `findInstanceOf ClassName [exact
  start]`; else wontfix (documented). Never worth deep kklass surgery.
- **Inherited unchanged:** Add/Insert/First/Last/Get/IndexOf/Sort/CustomSort/
  Exchange/Move/Pack. `Assign` stays the TList stub (FPC TObjectList doesn't
  override it either).

### NOT ported (wontfix)
1. `TComponentList`, `TClassList`, `TOrderedList/TStack/TQueue` (same unit) — out
   of scope (tqueuestack is its own roadmap unit).
2. `Notify` seam itself — bash TList has none; overriding removal paths is the
   whole mechanism here.
3. `FindInstanceOf` with CLASS HIERARCHY walk (AExact=False beyond exact match) —
   bash has no class tree introspection; at most exact-name match (P1 decision).

## 3. Deviations from house P0-skeleton convention

P0 ships a WORKING ownership core (ctor+dtor+_free+owns_objects) and NO stub
overrides: a stubbed Delete/Clear would corrupt list behavior (unlike a brand-new
class where stubs are inert). The class declaration therefore GROWS at P1
(Delete/Clear/Remove/Put overrides + Extract + BatchDelete) — deviation noted
here deliberately.

## 4. Parity & test model

Seed: `utcobjectlist.pp` mined verbatim (FPC-traceable rows; handles instead of
TObject, `.delete`-liveness instead of destructor flags — the TMyObject.IsFreed
pattern maps to "dispatcher fn gone"). Plus bash torture: double-free safety,
non-instance strings in an owning list, mixed live/dead handles, Clear/dtor on
empty, owns toggled mid-life (FPC allows it — property is writable), zero-fork
PATH='' on every path, dual-bash. Non-FPC cases → TEST_COVERAGE_NOTES rows.

## 5. Phases

- **P0 — probes + plan + ledger + skeleton (ctor/dtor/owns/_free) + smoke +
  baseline re-measure.** STOP.
- **P1 — removal-path overrides + Extract.** Delete/Clear/Remove/Put + Extract +
  BatchDelete + FindInstanceOf decision; FPC-seed parity file + ownership torture;
  dual-bash; sweep gate. STOP.
- **P2 — docs + closeout.** README (ownership contract, _free guard semantics,
  FPC delta table), docs/TObjectList.md (upstream reference), TEST_COVERAGE_NOTES
  finalized, ledger COMPLETE, final sweep. STOP.

## 6. Bash traps to respect

1. Free BEFORE `inherited Delete` (after it the element is gone) — but AFTER
   bounds validation (no free on invalid index).
2. `inherited X` resolves to the PARENT chain — inside Extract it deliberately
   bypasses our own Delete override (that's the feature, M2).
3. Handles with kklass-hostile names never exist (kklass validates instance
   idents at `new`) — but list elements may be ARBITRARY strings; `_free`'s
   `declare -F` guard is the only safe probe. Never `"$h".delete` unguarded.
4. Destructor runs BEFORE kklass teardown — `$count`/items still visible (M4).
5. `$()` never on the free path (subshell would lose nothing here but forks).

## 7. Deliverables

`kcl/tobjectlist/`: tobjectlist.sh, PLAN.md, tobjectlist_ledger.json, README.md,
docs/TObjectList.md, TEST_COVERAGE_NOTES.md, tests/001…+tests.sh. (No bench —
ownership adds one `declare -F` per removed element; nothing worth measuring.
If ever benched: TStopwatch.getTimeStamp per the house clock convention.)
