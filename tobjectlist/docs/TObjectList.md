# TObjectList — upstream FPC API reference

Source of truth: FPC `packages/fcl-base/src/contnrs.pp` —
`TObjectList = class(TList)` (:82–102). Implementation semantics: `Notify`
frees on `lnDeleted` when `FFreeObjects`; `SetItem` routes through `Put` ("Put
will take care of deleting old one in Notify"); `Extract` removes with
`lnExtracted` (no free). Parity oracle:
`packages/fcl-base/tests/utcobjectlist.pp` (9 fpcunit tests, mined verbatim in
`tests/002_FpcParity.sh`).

Upstream declaration shape:

```pascal
TObjectList = class(TList)
private
  FFreeObjects : Boolean;
protected
  Procedure Notify(Ptr: Pointer; Action: TListNotification); override;
  Function  GetItem(Index: Integer): TObject;
  Procedure SetItem(Index: Integer; AObject: TObject);
public
  constructor Create;                          // OwnsObjects = True
  constructor Create(FreeObjects : boolean);
  Function  Add(AObject: TObject): Integer;
  Function  Extract(Item: TObject): TObject;
  Function  Remove(AObject: TObject): Integer;
  Function  IndexOf(AObject: TObject): Integer;
  Function  FindInstanceOf(AClass: TClass; AExact: Boolean; AStartAt: Integer): Integer;
  Procedure Insert(Index: Integer; AObject: TObject);
  Function  First: TObject;
  Function  Last: TObject;
  property  OwnsObjects: Boolean read FFreeObjects write FFreeObjects;
  property  Items[Index: Integer]: TObject read GetItem write SetItem; default;
end;
```

## kcl mapping conventions

- A `TObject` is a **kklass instance handle** (its name string); `Free` is
  `$handle.delete`. Non-instance strings are legal ELEMENTS but are never
  freed (the `_free` liveness guard — see README).
- FPC routes ownership through ONE protected seam, `Notify(Ptr, lnDeleted)`.
  The bash `TList` has no notification mechanism, so this port overrides each
  removal path instead: `<free if owns>; inherited X "$@"` — kklass's
  `inherited` (rewritten to `$this.parent X`) supplies the parent behavior, so
  nothing is duplicated. Semantically equivalent: the set of paths that fire
  lnDeleted in FPC is exactly the set of overridden paths here.

## Members

### Create
```pascal
constructor Create;                       // OwnsObjects := True
constructor Create(FreeObjects: boolean);
```
→ **`TObjectList.new L [true|false]`** — owns default **true**; the token is
the `FreeObjects` boolean. Unknown token → rc 1, list still valid and owning
(house token convention, per TStopwatch `startnew`). Chains the TList
constructor via `inherited`.

### Destructor
FPC `TList.Destroy` clears the list → every element gets `lnDeleted` → freed
when owning. → **`L.delete`** — the destructor frees all owned `[0,count)`,
then kklass tears the instance down. (FPC-test headline `TestOwnsObjects`.)

### Notify (protected)
Not ported as a seam — see mapping conventions. **wontfix.**

### GetItem / SetItem / Items[] (default property)
→ inherited **`L.Get index`** / ownership-wrapped **`L.Put index item`**. Put
frees the OLD element **unless the new one is the same handle** — the exact
FPC `TList.Put` rule (Notify fires only when the pointer changes). bash has no
default-property `L[i]` sugar; `Get`/`Put` are the accessors.

### Add / Insert / First / Last / IndexOf
→ inherited unchanged from TList (`Add` returns the new count via RESULT —
NB: FPC's `Add` returns the ITEM'S INDEX = count−1; the bash TList predates
this port and returns the new COUNT — a documented TList-level delta, not
introduced here). No lnDeleted on any of these paths.

### Remove
```pascal
Function Remove(AObject: TObject): Integer;   // finds, deletes (frees), index
```
→ **`L.Remove item`** — frees when owning and present; RESULT = found index
or −1 (from the inherited TList.Remove).

### Extract
```pascal
Function Extract(Item: TObject): TObject;     // lnExtracted — NOT freed
```
→ **`L.Extract item`** — removes WITHOUT freeing (ownership released to the
caller): RESULT = the handle, rc 0; not present → RESULT "", rc 1. Internally
`inherited Delete idx` resolves PAST this class's own freeing `Delete`
override straight to `TList.Delete` — precisely lnExtracted.

### FindInstanceOf
```pascal
Function FindInstanceOf(AClass: TClass; AExact: Boolean; AStartAt: Integer): Integer;
```
→ **`L.FindInstanceOf ClassName [exact=true|false] [startAt=0]`** — first
element whose kklass class IS `ClassName` (exact) or DESCENDS from it
(`false`: walks `${class}_parent_class` up the chain), scanning from
`startAt`; miss → RESULT −1, rc 1; empty class name → rc 2. Matching is by
class NAME identity along the kklass chain; non-instance elements are skipped
via the liveness guard.

### OwnsObjects
```pascal
property OwnsObjects: Boolean read FFreeObjects write FFreeObjects;
```
→ **`L.owns_objects`** (kklass var): read `$(L.owns_objects)`, write
`L.owns_objects = "false"` — honored at the moment each removal happens, like
the writable FPC property.

## Deltas (bash-side, all pinned by tests)

| Topic | FPC | here |
|---|---|---|
| free of garbage / double-free | crash / UB | silent no-op (`_free` liveness guard — generalizes nil.Free-safe) |
| `Add` return value | item index (count−1) | new count (inherited bash-TList contract, predates this unit) |
| `Items[i]` sugar | default property | `Get`/`Put` methods |
| class matching in FindInstanceOf | TClass identity/inheritance | kklass class-NAME identity along `${class}_parent_class` |
