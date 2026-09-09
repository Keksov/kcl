# THashSet → bash port plan (kcl/thashset)

**Status: COMPLETE — P0, P1, P2, P3 and P4 are all done (2026-09-09).** Every
declared member has a real body, the suite is **149 checks green on bash 5.2.37
and 5.3.9**, and §7's deliverables all exist. Nothing in this plan is
outstanding; the per-phase DONE blocks below are the record.

**Roadmap position:** 6/7 (owner priority order, 2026-07-12).
**Source of truth:** FPC rtl-generics `generics.collections.pas` — `TCustomSet<T>` (:513–566: Add/Remove/Extract abstract trio, Clear, Contains, AddRange overloads :550–555, **UnionWith :2853 / IntersectWith :2861 / ExceptWith :2878 / SymmetricExceptWith** (impl after :2878), Count/Capacity/TrimExcess/OnNotify :561–565) + `THashSet<T>` (:570–612: backed by `TOpenAddressingLP<T, TEmptyRecord>` :574 — i.e. **FPC itself implements the set as a dictionary with empty values**; Extract :3019 → `Default(T)` on miss, Clear :3031).
**Target:** `kcl/thashset/thashset.sh` — kklass **instantiable** class `THashSet` over the tdictionary storage pattern minus values.
**Ledger:** `kcl/thashset/thashset_ledger.json`.
**Workflow:** phase → dual-bash tests → full master sweep → STOP → "go"; commits gated; no unit edits during a sweep.
**Conventions:** as `kcl/tdictionary/PLAN.md` §2.2–2.4/§6 — this unit REUSES the pinned tdictionary idioms verbatim (k-prefix, `+x` existence, single-quoted unset, `${k#k}` strip, `__ts_` locals).

---

## 1. Scoping analysis

FPC's own THashSet is a TDictionary<T, TEmptyRecord> in disguise (:574) — the bash port
is therefore the tdictionary storage layer with the value dimension deleted, plus the
**set algebra**, which is the actual reason to want this unit in bash (Union/Intersect/
Except/SymmetricExcept are eternally hand-rolled with dirty loops in scripts). Entirely
Tier A; every storage idiom arrives pre-validated by tdictionary tests/002.

### Ported

*(The `:5xx`/`:28xx`/`:30xx` numbers in this table are the P0 revision's and are
kept as written; the **release_3_2_2** tag's numbers — the ones every other file
now uses — are in the P2/P3 DONE blocks of §5 and, member by member, in
[docs/THashSet.md](docs/THashSet.md). The code is identical word for word.)*

| FPC | bash | Notes |
|---|---|---|
| `Create` / `Destroy` | `THashSet.new s` / `s.delete` | Destroy→Clear (events fire; pin S5) |
| `Add(AValue): Boolean` (:544) | `s.Add item` | rc 0 added / **rc 1 already-present, silent** — an answer, not an error (≠ TDictionary.Add's error semantics; pinned difference) |
| `Remove(AValue): Boolean` (:545) | `s.Remove item` | rc 0 removed / **rc 1 absent** — Boolean too (≠ TDictionary.Remove's always-rc0; pinned difference) |
| `Extract(AValue): T` (:546, :3019) | `s.Extract item` | hit: RESULT=item, removal, `extracted` event, rc 0; miss: RESULT='' rc 0 (`Default(T)` — same FPC ambiguity as ExtractPair; disambiguate via Contains; '' is a valid element) |
| `Clear` (:548) | `s.Clear` | event model pin S4 (THashSet.Clear :3031 delegates to the internal dictionary → likely empty-then-notify like tdictionary; verify) |
| `Contains(AValue): Boolean` (:549) | `s.Contains item` | rc; existence idiom |
| `AddRange(array of T): Boolean` (:550) | `s.AddRange i1 [i2 …]` | varargs; Boolean meaning pinned at P0 (all-added AND-fold vs any) |
| `UnionWith(ASet)` (:2853) | `s.UnionWith other` | Add each of other's (dups silently skipped; added events for genuinely-new only) |
| `IntersectWith(ASet)` (:2861) | `s.IntersectWith other` | FPC collects non-members FIRST, then removes — **snapshot two-pass, no mutate-while-iterate**; cloned |
| `ExceptWith(ASet)` (:2878) | `s.ExceptWith other` | Remove each of other's (silent misses) |
| `SymmetricExceptWith(ASet)` | `s.SymmetricExceptWith other` | impl pinned at P0 (likely per-item toggle; self-case ⇒ Clear — S3) |
| `Count` (:561) | `s.count` | computed `${#items[@]}` |
| `OnNotify` (:526) | `s.on_notify` var + `s.onNotify` setter + `Notify` seam | single event, cb `<inst> <item> <added\|removed\|extracted>`; `_notifyHook` reserved for future subclassing (no TObjectHashSet in FPC — none ported) |

Bash-convenience extras (TEST_COVERAGE_NOTES rows): `s.ToArray outVar` (lossless fill),
`s.ForEach cb` (snapshot semantics — tdictionary P3 clone), `s.Assign src` (copy),
`s.AddRangeFromArray arrName` (bulk from a caller array — varargs sibling).

### NOT ported (wontfix)

*(Line numbers below were re-read against the **release_3_2_2** tag at P4; the
P0 originals — `:602`, `:562–563`, `:576–592`, `:574` — came from a different
revision of the same file. `docs/THashSet.md` carries the full transcription.)*

1. **Hashing/comparer machinery** — `Create(const AComparer: IEqualityComparer<T>)`
   (:562), the `TOpenAddressingLP` backend (:535), the capacity family
   (`Capacity` :523 over `GetCapacity`/`SetCapacity` :556/:557, `TrimExcess`
   :524/:573) — the ENTIRE tdictionary API-v2 precedent applies verbatim: `declare -A`
   is the backend; comparers cannot back assoc lookups; capacity controls nothing.
2. **TSortedSet (:839–881) / TSortedHashSet (:883–941) / TAVLTree family**
   (`TAVLTree<T>` :812–824, `TIndexedAVLTree<T>` :826–837, `TCustomAVLTreeMap`
   :638) — balanced trees are pointless over a native hash; ordered iteration =
   sort the ToArray output at the boundary (README example composing
   `TArray.sort`, executed by tests/003).
3. **Enumerator objects / pointer enumerators** (`TCustomSetEnumerator` :480–489,
   `THashSetEnumerator` :537–543, `TPointersEnumerator` :545–552, `GetEnumerator`
   :503/:564) — ForEach/ToArray instead.
4. **`TEmptyRecord` trick** (:535, the global `EmptyRecord` :946) — internal; our
   storage stores `1` as the value.
5. **NUL bytes** in elements (bash limit).

---

## 2. Design decisions

### 2.1 Storage = tdictionary minus values
`${__inst__}_items` assoc; membership = `items["k$item"]=1`. All four pinned idioms
land unchanged (prefix vs empty-subscript, `+x` existence, `pk=…; unset 'ref[$pk]'`,
`${k#k}` iteration strip). tests/00X reruns a REDUCED torture (the full 34-key matrix is
already proven in tdictionary/tests/002 — here a representative subset guards against
drift: '', ']', '*', newline, `$(echo pwned)`, k/kk, unicode).

### 2.2 Boolean-rc surface — the loud difference from TDictionary
`Add`/`Remove` return Booleans in FPC sets (vs dictionary's raise-on-dup Add and
always-true Remove). The port keeps rc AS the Boolean and stays SILENT on rc=1 (no
debug msg — it is not an error path). README carries a comparison box
(TDictionary vs THashSet member-by-member) because the two units will be used side by side.

### 2.3 Set algebra — FPC loop semantics, self-operation edges defined
- UnionWith: iterate other's snapshot, `Add` each (added events only for new).
- IntersectWith: two-pass clone of :2861 (collect victims, then remove) — makes
  `s.IntersectWith s` a defined no-op.
- ExceptWith: iterate other's snapshot, `Remove` each. **`s.ExceptWith s` ⇒ Clear-like
  full drain** (FPC same — iterating OTHER == self while removing… :2878 iterates the
  ARGUMENT's Ptr — self-case behavior pinned at P0 and tested explicitly).
- SymmetricExceptWith: pinned at P0; self-case ⇒ empty (a⊕a=∅) — verified against impl.
- Other must be a live THashSet instance (validated via its storage `@a` check before
  ANY mutation — the Assign source-validation lesson).
- Events fire per element with the standard actions (exact order = iteration order,
  UNSPECIFIED like all hash iteration; tests compare sorted or use sets).

### 2.4 Events
Single `onNotify` + public virtual `Notify` seam + `_notifyHook` — the house pattern
(cost when unhooked = one `[[ -n ]]`). No TObject* subclass exists in FPC for sets, so
the seam is future-proofing only (documented).

> **Amended at P3 (2026-09-09).** The *seam* is indeed ours, but the plumbing is
> not: FPC's set has no `Notify` at all — `TCustomSet.OnNotify` (:526) is a
> property over abstract `Get/SetOnNotify` (:495/:496), and `THashSet` routes the
> internal dictionary's `OnKeyNotify` through a private forwarder
> (`SetOnNotify` :2530, `InternalDictionaryNotify` :2500) whose sender is the
> SET. `SetOnNotify`'s `if Assigned(AValue) … else nil` is the FPC original of
> the `_notify` gate, so the gate is parity rather than an optimisation. With
> `_notifyHook` in it the unhooked cost is one `[[ ]]` carrying **two** string
> tests. Details in the P3 DONE block in §5.

## 3. Pinned semantics (verify/finalize at P0)

| # | Semantic | Source | Status |
|---|---|---|---|
| S1 | Add dup → False, NO event, no mutation | THashSet.Add via TryAdd | verify impl line |
| S2 | Remove miss → False silent; hit → True + removed event | THashSet.Remove :~3005 | verify |
| S3 | SymmetricExceptWith algorithm + self-case ⇒ ∅ | impl after :2878 | READ at P0 |
| S4 | Clear event model (empty-then-notify like tdictionary, or per-remove?) | :3031 → internal dict Clear | verify |
| S5 | Destroy → Clear (events during delete) | THashSet.Destroy :603 | verify |
| S6 | Extract miss → Default(T), rc 0, NO event | :3019–3029 | pinned |
| S7 | AddRange Boolean = AND-fold of per-item Adds? | :550 impl | READ at P0 |
| S8 | UnionWith/ExceptWith self-operation behavior | :2853/:2878 with ASet==Self | READ at P0, test both |
| S9 | OnNotify actions on set ops = plain added/removed per element | TCustomSet plumbing | verify |

All nine were resolved at P0 (the resolutions are in `thashset_ledger.json`,
`execution_log` entry 2) and each has been **closed by a test** since: S1/S2/S4/
S6 in `tests/002` and `tests/006`, S3/S7/S8 in `tests/005`, S5 and S9 in
`tests/006` (S9 is a full sequence matrix, not just the action names — see the
P3 DONE block). The `:2853`/`:3002`-style line numbers in the table above are
from the revision P0 read; the tag's numbers are in the P2/P3 DONE blocks.

## 4. Parity & test model

Seeds: rtl-generics/tests scanned at P0 for set coverage (tests.generics.sets.pas or
stdcollections — mined if present). Basis: S1–S9 pins + matrices: membership lifecycle
incl. '' element; Boolean-rc contract vs tdictionary comparison rows; algebra truth
tables on known sets (A∪B, A∩B, A∖B, A⊕B against hand-computed results, sorted-compare);
self-op edges (S8, a⊕a=∅, a∖a=∅, a∪a=a, a∩a=a); empty-set operands both sides;
disjoint/subset/superset/overlap shapes; event recorders on algebra ops (set-compare of
sequences); Assign/ToArray/ForEach clones of tdictionary cases; reduced storage torture;
zero-fork PATH=''; dual-bash. Non-FPC cases → TEST_COVERAGE_NOTES rows.

## 5. Phases

- **P0 — pins + skeleton.** READ S3/S7/S8 impls + verify the rest; skeleton + runner;
  reduced torture; baseline re-measure. STOP.
- **P1 — membership core.** Add/Remove/Contains/Extract/Clear/count + ToArray/ForEach/
  Assign extras + Boolean-rc contract tests. Sweep gate. STOP.
- **P2 — set algebra.** UnionWith/IntersectWith/ExceptWith/SymmetricExceptWith +
  AddRange/AddRangeFromArray + truth tables + self-op edges + operand validation. Sweep
  gate. STOP.

  **DONE 2026-09-09.** All six `TSet._pending … P2` stubs replaced; `Notify` is the
  only sentinel left (P3). New suite file `tests/005_SetAlgebra.sh`, 45 cases,
  **red-first 38 FAIL / 45 against the stub code**, 0 after. Unit suite 92/92 on
  bash 5.2.37 and on 5.3.9 (was 47/47).

  *FPC quoted from the **release_3_2_2** tag of
  `packages/rtl-generics/src/generics.collections.pas`. The `:2815/:2853/:2861/:2878/
  :2886` and `:3002/:3009/:3019/:3031` numbers recorded at P0 came from a different
  revision of the same file — the code is identical word for word, only the line
  numbers moved. The refs below (and in the ledger, the unit header and the README)
  are the tag's.*

  | member | FPC | quoted implementation |
  |---|---|---|
  | `AddRange` | `TCustomSet<T>.AddRange(constref AValues: array of T)` **:2379** | `Result := True; for i in AValues do Result := Add(i) and Result;` — an AND-fold in which `Add` runs for **every** item (the `and` is on the right of the assignment, nothing is short-circuited), and an empty array leaves `Result` True |
  | `UnionWith` | **:2417** | `for i in AHashSet.Ptr^ do Add(i^);` |
  | `IntersectWith` | **:2425** | `LList := TList<PT>.Create; for i in Ptr^ do if not AHashSet.Contains(i^) then LList.Add(i); for i in LList do Remove(i^);` — two-pass, so nothing is deleted while the table is walked |
  | `ExceptWith` | **:2442** | `for i in AHashSet.Ptr^ do Remove(i^);` |
  | `SymmetricExceptWith` | **:2450** | `for i in AHashSet.Ptr^ do if Contains(i^) then LList.Add(i) else Add(i^); for i in LList do Remove(i^);` — two-pass over the OPERAND |
  | Booleans driven by the four | `THashSet<T>.Add` **:2559**, `Remove` **:2566**, `Contains` **:2593** | the abstract trio `TCustomSet` (declared :474–527, `Add` abstract at :505) is written against |

  Parity oracle mined: `packages/rtl-generics/tests/tests.generics.sets.pas`
  `Test_Set_General` **:86–152** — its hand-computed truth table is ported case for
  case in section A of 005. Two mappings were needed: `NumbersC := T.Create(NumbersA)`
  (the copy ctor) → `C.Assign A`, and `NumbersC.AddRange(NumbersB)` (:117, :146 — the
  `TEnumerable` overload **:2397**, a whole SET as the source) → `C.AddRange` over B's
  elements from `ToArray` for the Boolean half plus `C.UnionWith B` for the membership
  half, since our `AddRange` surface is varargs (frozen at P0).

  **Implementation.** The six members drive the public `$this.Add` / `$this.Remove` /
  `$this.Contains` instead of re-implementing the storage idioms: that is what
  `TCustomSet` itself does (its four procedures call the abstract `Add`/`Remove`), it
  keeps the P3 event stream identical to the same calls made by hand, and it leaves
  one copy of the k-prefix idioms in the unit. Measured cost: 40 ms per 1000 internal
  `$this.Add` against 27 ms for the same loop inlined — a 1.5× premium on a path whose
  budget is 3×, so faithfulness won. Every op snapshots the operand's keys
  (`"${!ref[@]}"`) **before** self is touched (§6.2) and validates the operand by CLASS
  (`TSet._isSet`, R5) **before** any mutation, so a rejected operand leaves the storage
  byte-identical (asserted with `declare -p` before/after, not just with `Count`).
  `AddRangeFromArray` validates its INPUT name through `TSet._outName`/`kk._outName`
  (rc 2, the tinifile `SetStrings` precedent) and refuses an associative array, a
  scalar and an unset name with rc 2 as well.

  **Self-operation edges, all tested:** `a.UnionWith a` = a, `a.IntersectWith a` = a
  (pass 1 collects nothing), `a.ExceptWith a` = ∅ (full drain), `a.SymmetricExceptWith a`
  = ∅ (everything is marked, then removed). The snapshot is what makes the last two
  *defined* rather than a walk over a shrinking table.

  **Deviation / extra fix — P2-F1 (pre-existing, on the P2 error path).**
  `TSet._isSet` fed the operand name straight into `${!name_class}`, and an indirect
  expansion of a non-identifier makes bash print `not a name_class: invalid variable
  name` on stderr — so `A.Assign 'a[0]'` answered rc 1 *with a diagnostic*, against
  kcl/README.md §1.2 ("no stdout, no stderr"). All four new ops share that helper, so
  an identifier-shape guard was added there; `Assign` (P1) inherits the fix. Red-first
  proof and 40 rejections (8 non-identifier shapes × 5 members) are in 005.

  **Test-file change outside 005:** `tests/001_Skeleton.sh`'s sentinel case asserted
  `S.UnionWith y` → `__ths_pending__:UnionWith`. It now asserts the opposite half as
  well — `UnionWith` answers rc 1 on a non-set operand and leaves **no** sentinel,
  while `Notify` still returns one. No assert was weakened.
- **P3 — events.** onNotify/Notify/_notifyHook + recorder tests on all mutation paths
  incl. algebra ops. Sweep gate. STOP.

  **DONE 2026-09-09.** The last stub (`TSet._pending Notify P3`) is gone, and
  with it the `TSet._pending` helper itself — **every declared member now has a
  real body**. New suite file `tests/006_Events.sh`, 55 cases, **red-first
  46 FAIL / 55** against the stub code, 0 after. Unit suite **148/148** on bash
  5.2.37 and on 5.3.9 (was 92/92; +55 from 006 and +1 from 001).

  *FPC quoted from the **release_3_2_2** tag, same file as P2.*

  **What FPC actually has — and the one place the plan was wrong.** §2.4 called
  the seam "the house pattern … future-proofing only". That is right about the
  seam but understates the plumbing: a set in FPC has **no** `Notify` at all.
  `TCustomSet<T>.OnNotify` (**:526**) is a property over the abstract
  `GetOnNotify`/`SetOnNotify` pair (**:495**/**:496**), and `THashSet`
  implements the pair by re-routing its internal dictionary:

  | FPC | quoted implementation |
  |---|---|
  | `THashSet<T>.SetOnNotify` **:2530** | `FOnNotify := AValue; if Assigned(AValue) then FInternalDictionary.OnKeyNotify := InternalDictionaryNotify else FInternalDictionary.OnKeyNotify := nil;` |
  | `THashSet<T>.InternalDictionaryNotify` **:2500** | `FOnNotify(Self, AItem, AAction);` — the **sender is the SET**, not the storage |
  | `THashSet<T>.GetOnNotify` **:2525** | `Result := FInternalDictionary.OnKeyNotify;` — reads back the private FORWARDER, not the assigned handler (an upstream asymmetry; **FPC wins** on the routing, but not here: `$(s.on_notify)` returns what was set, and the divergence is in the README table) |
  | `THashSet<T>.Destroy` **:2554** | `FInternalDictionary.Free;` — freeing the dictionary runs its `Clear`, so **delete notifies `removed` per element** (S5) |
  | `Add` **:2559** / `Remove` **:2566** / `Extract` **:2576** / `Clear` **:2588** | the cnAdded / cnRemoved / cnExtracted sources; `Extract`'s miss exits **before** `DoRemove`, so it is silent (S6) |

  The `if Assigned(AValue) … else nil` in `SetOnNotify` is the FPC original of
  the `_notify` gate: with no listener the dictionary is not hooked and nothing
  is dispatched. So the gate is parity, not an optimisation.

  Parity oracle mined and ported case for case in section A of 006:
  `tests.generics.sets.pas` `Test_TCustomSet_Notification` **:261–338** (entered
  from `Test_THashSet_Notification` **:340**). Its `LSet` deliberately carries
  no listener, which also pins that events belong to the *receiver*, not the
  operand. Its two `EnumerableStrings*` `AddRange` overloads (**:277**/**:278**)
  map to our varargs `AddRange`, the same mapping P2 made. The oracle's final
  block (**:330–336**) is the S5 proof: `ASet.Add('Polandball')` then
  `ASet.Free` expects `cnAdded` followed by `cnRemoved`.

  **Implementation.** `THashSet.Notify` is the public virtual seam: `declare -F`
  on `$on_notify` **at fire time** (the name is a plain writable var, so it may
  be set before the function exists or unset afterwards), the call
  `"$on_notify" "$__inst__" "$item" "$action" || :` with the status **ignored**
  (a Pascal event is a `procedure`), a dangling name reduced to one `kk.debug`
  line and a no-op, and `return 0` on every path so the gate cannot leak a
  status into the mutating member. `var _notifyHook` joins the surface with the
  tdictionary semantics (a subclass that overrides `Notify` arms it in its
  constructor); the gate in `TSet._notify` and the `Clear` fast path became
  `[[ -n "$on_notify" || -n "$_notifyHook" ]]`. `proc onNotify` is the
  validating setter over the same slot: `''` detaches (rc 0), a name that is not
  a function is **rc 2** + `kk.debug` with the installed hook **unchanged**,
  and the house spelling `s.on_notify = "cb"` keeps working. `Destroy` now runs
  `$this.Clear` before `TSet._teardown` (S5) — the virtual call, so a descendant
  that overrides `Clear` or `Notify` is honoured there too.

  **Sequences pinned (S9).** Exact where deterministic, multiset where hash
  order is involved: `Add` new → one `added`, duplicate → nothing; `Remove`/
  `Extract` hit → one `removed`/`extracted` fired **after** the element is gone
  (the callback's `Contains` is false and `Count` is already decremented), miss
  → nothing; `Clear` → storage emptied first (every callback sees `Count` 0),
  then one `removed` per old element, and nothing at all on an empty set;
  `s.delete` → one `removed` per element; `Assign` → every `removed` strictly
  before every `added` (asserted by index, not by shape); `AddRange`/
  `AddRangeFromArray` → `added` for the genuinely new only, in argument order;
  `UnionWith` → `added` for operand-only; `IntersectWith` → `removed` for the
  victims; `ExceptWith` → `removed` for the hits; `SymmetricExceptWith` →
  `added` (pass 1) all before `removed` (pass 2); the self-ops `a∪a`/`a∩a` fire
  **nothing** while `a∖a`/`a⊕a` fire `removed` × |a|; an empty operand and a
  rejected operand fire nothing.

  **Re-entrancy rule pinned and documented:** callbacks run after the mutation,
  every loop walks a snapshot, so a callback that mutates the set leaves it
  consistent (`Count` == raw storage == `ToArray`, asserted, not just `Count`)
  and its own mutations are delivered as further events. Terminating the
  recursion is the callback's job. Three cases: add-during-`Clear`,
  remove-during-`UnionWith`, `Clear`-during-`Add`, plus a bounded 5-deep
  recursion.

  **Hook-less cost.** 1000 `Add` calls: **220 ms** unhooked vs **566 ms** with a
  do-nothing listener on bash 5.2.37; **189 ms** vs **495 ms** on 5.3.9 (2.6×
  for the dispatch + callback). The unhooked figure is indistinguishable from
  the P2 baseline (219 ms / 188 ms), i.e. the second string test in the gate is
  below measurement noise; a paired before/after benchmark of `Add`/`Contains`/
  `Remove` over 1k showed `Contains` — which does not call the gate — unchanged,
  confirming that the extra `var` costs nothing per frame.

  **Deviations from the letter of the assignment, both deliberate:**
  1. The gate is `[[ -n "$on_notify" || -n "$_notifyHook" ]]` as instructed,
     which is **one `[[ ]]` with two string tests**, not one string test. The
     two are mutually exclusive requirements; `_notifyHook` won, as in
     tdictionary (three tests there) and tqueuestack (two). Measured above as
     below noise.
  2. `TSet._pending` was **deleted**, not left dead: its own comment said "thin
     sentinels; removed as phases land", and no member calls it any more.
     `tests/001` and both surface sweeps (005 §H, 006 §I) still assert that no
     member answers with `__ths_pending__`.

  **Test-file changes outside 006.** `tests/001_Skeleton.sh`: the sentinel case
  now demands that `Notify` is real too (rc 0, no sentinel) instead of asserting
  the sentinel, and a new case pins that `onNotify`/`_notifyHook` exist and
  start empty (9 → 10 cases). `tests/005_SetAlgebra.sh` §H: the two-member
  exclusion is gone — the sweep runs all 17 members, `Notify` and `onNotify`
  included. No assert was weakened.
- **P4 — docs, bench, closeout.** README (API + the TDictionary-vs-THashSet comparison
  box + sorted-iteration composition example), docs/THashSet.md (upstream FPC reference
  per kcl docs convention, TCustomSet chain), bench.sh (Add/Contains per-op, 1k×1k
  UnionWith/IntersectWith, O(1) flat check, zero-fork), TEST_COVERAGE_NOTES finalized,
  ledger COMPLETE, final sweep. STOP.

  **DONE 2026-09-09.** No unit code was changed — `thashset.sh` is byte-identical
  to the P3 commit. What was written:

  | File | State |
  |---|---|
  | `bench.sh` | **new**, 6 sections (see the numbers below); `TStopwatch.getTimeStamp` clock, deterministic sizes, no `$RANDOM`, rc 0, clean under `bash -eu` with empty stderr |
  | `docs/THashSet.md` | **new**, the house header block (Upstream reference / Ported / Roadmap / Wontfix / Return contract) + the `TCustomSet`/`THashSet` API transcribed from the **release_3_2_2** tag with line numbers + a "how the bash port maps" table + the divergence table |
  | `TEST_COVERAGE_NOTES.md` | **new**, the house protocol paragraph, a class legend and **one table per test file with every one of the 149 cases** (10 / 17 / 11 / 11 / 45 / 55) |
  | `README.md` | status → COMPLETE (P0–P4); new **TDictionary-vs-THashSet comparison box** (20 rows), new **Ordered iteration** section with the `ToArray` + `TArray.sort` example and its real output, new **Performance** section with the bench table for both bashes, the Tests section rewritten as a per-file table; every "pending / P3 / P4 will" wording gone |
  | `tests/003_Contract.sh` | +1 case (11 total): the README sorted-iteration example run end to end |
  | `../README.md` §2 | the thashset row rewritten as a complete unit |
  | `thashset_ledger.json` | phase P4 + tasks P4.1/P4.2 done, bench numbers for both bashes, status COMPLETE |

  **The one test added, red-first.** `003.readme-sorted` was first written
  asserting the *hash* order (`pear apple fig banana cherry`) and run against
  the real code: **1 FAIL / 149**, reporting the true value
  `apple banana cherry fig pear`. The expectation was then corrected and the
  suite went 149/149. The case lives in `003_Contract.sh` — deliberately, and
  flagged in the file — because the composition it runs is the *contract*
  standing in for the `TSortedSet`/`TSortedHashSet` wontfix.

  **Bench numbers (2026-09-09, Windows 11 / MSYS2).** Gate: no algebra op may
  cost more than **3×** a 1k `Add` loop; `Contains` must be **flat** (ratio
  < 2.0) between 100 and 10 000 elements.

  | Measurement | 5.2.37 | 5.3.9 |
  |---|---|---|
  | `Add` n=1000 / n=5000 | 249.1 / 237.9 µs/op | 239.0 / 235.6 µs/op |
  | `Contains` hit n=1000 / n=5000 | 198.7 / 195.3 µs/op | 203.9 / 204.0 µs/op |
  | `Contains` miss n=1000 / n=5000 | 208.6 / 200.7 µs/op | 206.4 / 204.9 µs/op |
  | `Remove` n=1000 / n=5000 | 258.2 / 229.7 µs/op | 234.4 / 230.0 µs/op |
  | baseline 1k `Add` | 219 ms | 233 ms |
  | `UnionWith` 1k disjoint | 281 ms = **1.2×** PASS | 269 ms = **1.1×** PASS |
  | `IntersectWith` 1k×1k 50% | 146 ms = **0.6×** PASS | 139 ms = **0.5×** PASS |
  | `ExceptWith` 1k×1k 50% | 261 ms = **1.1×** PASS | 274 ms = **1.1×** PASS |
  | `SymmetricExceptWith` 1k×1k 50% | 513 ms = **2.3×** PASS | 536 ms = **2.2×** PASS |
  | `Contains` @100 vs @10 000 | 195.8 vs 193.8 µs/op = **0.9×** PASS | 242.1 vs 244.0 µs/op = **1.0×** PASS |
  | 1k `Add` unhooked → hooked | 235 → 624 ms = **2.6×** | 281 → 651 ms = **2.3×** |
  | zero-fork | `$BASHPID` unchanged over all 17 methods; `PATH=''` sequence correct | same |

  `SymmetricExceptWith` is the expensive one by construction — FPC's :2450 pays
  a `Contains` plus either an `Add` or a deferred `Remove` for **every** element
  of the operand — and it is still comfortably inside the 3× gate. The flat
  `Contains` ratio is the O(1) claim: over a set **100× larger** the per-op cost
  does not move, because `declare -A` is a real hash table and the port adds no
  scan of its own.

  **Deviations from the letter of the assignment.** Three, all small:
  1. The `README` bullet asked for "no `P3`" wording; the two surviving
     mentions are *historical* (a Performance line comparing against the P2/P3
     baselines, and the file name `004_ReviewP2.sh`), not status claims.
  2. `bench.sh` does not set `set -eu` itself — neither `tqueuestack/bench.sh`
     nor `tdictionary/bench.sh` does, and the brief made that conditional. It
     was *run* under `bash -eu` (rc 0, empty stderr) and every Boolean member is
     called with `|| :`, the `tests/005` shape.
  3. The `PATH=''` probe inside `bench.sh` redirects every `func` call to
     `/dev/null`: the probe is itself a `$( )`, so `Count`/`ToArray`/`Extract`
     print their value there (the kklass return contract). Caught by the first
     run, which reported `63055a06|3|0|5|5|a|0`.

  **Docs drift corrected while transcribing the tag.** The `out_of_scope`
  entries written at P0 carried the *other* revision's numbers for three items
  (comparer ctor `:602` → **:562**, `TEmptyRecord` `:574` → **:535**,
  enumerators `:576–592` → **:480–489** / **:537–552**, which in the tag is the
  `TPair`/`TAVLTreeNode` block, not an enumerator at all). `docs/THashSet.md`
  carries the tag's numbers and says so; the ledger entries were re-pointed in
  the same pass.

## 6. Bash traps to respect

1. All tdictionary storage idioms verbatim; `__ts_` local prefix in nameref methods.
   **This line was a claim the P1 code did not honour** (kcl review 2026-09-06,
   findings G2-01/G2-06): the deletion idiom was written `unset "${__inst__}_items[$pk]"`
   — DOUBLE quotes, so `unset` re-parsed the substituted subscript. Elements containing
   `]` `[` `$` `'` `"` `\` or a backtick were not removed (rc 0 all the same) and `$( )`
   content was EXECUTED. Fixed in the kcl P2 phase with the real single-quoted form
   `unset 'ref[$pk]'`; tests/002 now removes and extracts the exotic set, which the
   original torture did not (it covered Add/Contains/ToArray only — hence 23/23 green
   over a HIGH defect). When a plan says "verbatim", a test has to prove it.
2. Algebra ops snapshot the OTHER set's keys BEFORE mutating self (and self's keys
   before removing during IntersectWith) — `"${!ref[@]}"` array capture first.
3. rc=1 from Add/Remove is an ANSWER — never route it through error paths, never
   debug-log it; but DO `kk._return ""` where funcs early-return (Extract has none —
   miss is rc 0; the trap applies to arg-validation paths only).
4. Operand validation BEFORE any mutation (atomicity — the Assign lesson).
5. `$()`-mutation caveat in tests (file-redirect stderr).
6. Never edit the unit mid-sweep.

## 7. Deliverables

`kcl/thashset/`: thashset.sh, PLAN.md, thashset_ledger.json, README.md,
docs/THashSet.md, bench.sh, TEST_COVERAGE_NOTES.md, tests/001…+tests.sh.

**All delivered as of P4 (2026-09-09):** `thashset.sh` (17 methods + 2 event
vars, every one with a real body), `PLAN.md`, `thashset_ledger.json`,
`README.md`, `docs/THashSet.md`, `bench.sh`, `TEST_COVERAGE_NOTES.md`, and
`tests/001_Skeleton.sh` … `006_Events.sh` + `tests/tests.sh` — 149 cases, 0 FAIL
on bash 5.2.37 and on bash 5.3.9.
