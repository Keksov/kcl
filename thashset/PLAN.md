# THashSet → bash port plan (kcl/thashset)

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
| `OnNotify` (:565) | `s.onNotify` property + `Notify` seam | single event, cb `<inst> <item> <added|removed|extracted>`; `_notifyHook` reserved for future subclassing (no TObjectHashSet in FPC — none ported) |

Bash-convenience extras (TEST_COVERAGE_NOTES rows): `s.ToArray outVar` (lossless fill),
`s.ForEach cb` (snapshot semantics — tdictionary P3 clone), `s.Assign src` (copy),
`s.AddRangeFromArray arrName` (bulk from a caller array — varargs sibling).

### NOT ported (wontfix)

1. **Hashing/comparer machinery** — `Create(IEqualityComparer)` (:602), the
   TOpenAddressingLP backend, capacity family (`Capacity/TrimExcess/SetCapacity`
   :562–563) — the ENTIRE tdictionary API-v2 precedent applies verbatim: `declare -A`
   is the backend; comparers cannot back assoc lookups; capacity controls nothing.
2. **TSortedSet / TSortedHashSet / TAVLTree family** (:the AVL block) — balanced trees
   are pointless over a native hash; ordered iteration = sort the ToArray output at the
   boundary (README example composing `TArray.sort`).
3. **Enumerator objects / pointer enumerators** (:576–592) — ForEach/ToArray instead.
4. **`TEmptyRecord` trick** (:574) — internal; our storage stores `1` as the value.
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
- **P3 — events.** onNotify/Notify/_notifyHook + recorder tests on all mutation paths
  incl. algebra ops. Sweep gate. STOP.
- **P4 — docs, bench, closeout.** README (API + the TDictionary-vs-THashSet comparison
  box + sorted-iteration composition example), docs/THashSet.md (upstream FPC reference
  per kcl docs convention, TCustomSet chain), bench.sh (Add/Contains per-op, 1k×1k
  UnionWith/IntersectWith, O(1) flat check, zero-fork), TEST_COVERAGE_NOTES finalized,
  ledger COMPLETE, final sweep. STOP.

## 6. Bash traps to respect

1. All tdictionary storage idioms verbatim; `__ts_` local prefix in nameref methods.
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
