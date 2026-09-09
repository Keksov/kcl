# thashset — test coverage notes

**Status: FINALIZED at P4 (2026-09-09).** Suite `001`–`006` = **149 cases**,
green on bash 5.2.37 (primary) and on bash 5.3.9 (secondary). The per-file row
counts below sum to 149 — 10 + 17 + 11 + 11 + 45 + 55 — and every case in the
suite has a row.

Protocol (house): **invented / source-pinned** cases get a row here;
**FPC-traceable** cases cite their seed procedure in the Basis column instead of
being argued from first principles. Seeds, both in
`packages/rtl-generics/tests/tests.generics.sets.pas` at the **release_3_2_2**
tag:

* `Test_Set_General` **:86–152** — the hand-computed algebra truth table
  (entered for `THashSet` from `Test_HashSet_General` :231–234). Ported case for
  case in `005_SetAlgebra.sh` §A.
* `Test_TCustomSet_Notification` **:261–338** — the notification oracle
  (entered from `Test_THashSet_Notification` :340–343). Ported case for case in
  `006_Events.sh` §A.

Implementation line refs are into
`packages/rtl-generics/src/generics.collections.pas` at the same tag —
`TCustomSet<T>` declared :474–527 with the algebra at :2379–2467, `THashSet<T>`
declared :531–574 with the implementation at :2500–2601. The S-column values
(`S1`…`S9`) are the pins of `PLAN.md` §3, each of which carries its own source
anchor. `G*`/`P*-F*` values are finding IDs from the 2026-09-06 kcl review and
from this unit's own phases (`thashset_ledger.json`).

**Classes.**

| Class | Meaning |
|---|---|
| `contract` | the kcl contract: rc mapping, `RESULT`, silence, validation, lifecycle, zero-fork |
| `behavior` | a semantic read out of the FPC source (an S-pin, an algebra result, a Boolean answer) |
| `event` | a `Notify` sequence, the callback signature, or the seam itself |
| `representation` | bash storage and string specifics — subscripts, exotic elements, injection |
| `boundary` | an edge FPC never exercises: the `''` element, an empty operand, zero arguments, a self-operation |

---

## 001_Skeleton.sh — ctor core and the storage idioms (P0) — 10 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 001.storage-init | Create, Count, on_notify | a fresh set: `${inst}_items` is a live assoc, `Count` 0, `on_notify` empty | contract | kklass instance lifecycle; FPC `Create` :2544 only allocates the internal dictionary, so there is no bash-observable analog |
| 001.count-computed | Count | subscripts injected straight into the storage are counted | behavior | `Count` ≡ `${#items[@]}` by design; FPC `GetCount` :2510 likewise delegates — no stored mirror to drift |
| 001.torture-exotic | (storage idioms) | 9 exotic subscripts coexist and stay distinct: `''`, `]`, `*`, `a b`, newline, `$(echo pwned)`, `k`, `kk`, `café` | representation | bash assoc-subscript semantics; a reduced form of `tdictionary/tests/002` (the full 34-key matrix is proven there) |
| 001.empty-subscript | (storage idioms) | the `''` element lands on subscript `k`, and the empty subscript is never used | representation | bash 5.2 rejects `arr['']`; hence the `k` prefix |
| 001.no-sentinel | UnionWith, Notify | neither answers with `__ths_pending__`: `UnionWith` is rc 1 on a non-set operand, `Notify` is a quiet rc 0 | contract | the P2/P3 stub removal (`TSet._pending` is gone from the unit) |
| 001.event-surface | on_notify, _notifyHook, onNotify | all three exist and both hook slots start empty | contract | P3 surface; FPC has no default handler either (`SetOnNotify` :2530 leaves the dictionary unhooked) |
| 001.teardown | Destroy | `s.delete` leaves no `${inst}_items` behind | contract | destructor contract; FPC `Destroy` :2554 frees the internal dictionary |
| 001.resource | (unit) | a second `source` of the unit is a clean no-op | contract | the re-source guard (house rule) |
| 001.isolation | Create | two sets have independent storage | contract | per-instance storage |
| 001.zero-fork | Create, Count, Destroy | ctor, `Count` and teardown run under `PATH=''` | contract | no external commands on any path (kcl §1.6) |

## 002_MembershipCore.sh — the membership core (P1) — 17 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 002.add-bool | Add, Count | new → rc 0; duplicate → rc 1, **silent**, no mutation | behavior | S1 — FPC `Add` :2559 answers `not ContainsKey` and guards the write |
| 002.contains | Contains | hit rc 0, miss rc 1 | behavior | FPC `Contains` :2593 |
| 002.remove-bool | Remove, Count | hit → rc 0; absent → rc 1, **silent** | behavior | S2 — FPC `Remove` :2566 answers `LIndex >= 0` |
| 002.extract | Extract, Contains | hit `RESULT`=item, miss `RESULT`=`''`, **rc 0 both**, the hit removes | behavior | S6 — FPC `Extract` :2576 exits `Default(T)` at :2582 before `DoRemove` |
| 002.empty-element | Add, Contains, Count, Remove | `''` is a first-class element through the whole lifecycle | boundary | the seeds use integer-derived elements only; validity of `''` follows from `T = string` |
| 002.exotic-add | Add, Contains, ToArray | 8 exotic elements stay distinct and come back losslessly | representation | inputs are the oracle |
| 002.exotic-remove | Remove, Contains, Count | 15 exotic elements are really **removed**, not silently kept | representation | finding G2-01 — the deletion idiom used double quotes, so `unset` re-parsed the substituted subscript |
| 002.exotic-extract | Extract, Contains | the same 15 come back **verbatim** and leave the set | representation | G2-01 (the other half; the old torture covered Add/Contains/ToArray only) |
| 002.no-exec | Remove, Extract | a `$( )` and a backtick element are not **executed** (canary file) | representation | G2-01 — the double-quoted `unset` executed the content |
| 002.foreach | ForEach | every element is visited exactly once | contract | no FPC analog (enumerators are wontfix); the contract is defined here |
| 002.foreach-snapshot | ForEach, Add | a callback that adds during the walk still visits exactly the 3 originals | contract | snapshot semantics, cloned from the tdictionary P3 decision (FPC enumeration over mutation is UB) |
| 002.clear | Clear, Count, Contains | `Clear` empties the set and membership is gone | behavior | FPC `Clear` :2588 |
| 002.assign | Assign, ToArray | copies the source, drops the previous contents; an unknown operand is rc 1 | contract | the `Create(ACollection)` :2359 analog; operand validation is bash-side |
| 002.assign-atomic | Assign | a rejected operand leaves the target **untouched** | contract | R5 / the operand-validation atomicity rule (PLAN §6.4) |
| 002.gate-off | Add, Extract, Remove | with no listener the operations still work and nothing is dispatched | contract | FPC's own model: `SetOnNotify` :2530 leaves `OnKeyNotify` nil when nothing is assigned |
| 002.isolation | (all) | two sets do not see each other's elements | contract | per-instance storage |
| 002.zero-fork | Add, Contains, Remove, Extract, ToArray, Count, Destroy | the full membership lifecycle under `PATH=''` | contract | kcl §1.6 |

## 003_Contract.sh — the kcl-wide contract (review P1) — 11 cases

The first ten are the near-identical contract block every kcl unit carries; the
eleventh is this unit's deliberate exception (see its own row).

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.parse | (unit) | `bash -n` on `thashset.sh` is clean | contract | house source-integrity rule |
| 003.no-open-quote | (unit) | no `printf '…` is left open at end of line | contract | the P1 sweep that put a **real newline** inside a format string while every behavioural test stayed green |
| 003.setu-load | (unit) | the unit loads under `set -eu` with empty stderr | contract | X-SETU / decision D7 |
| 003.setu-reload | (unit) | loading it **twice** under `set -eu` is a clean no-op | contract | X-SETU + the re-source guard |
| 003.setu-main | Add, Count, Contains, Remove, Clear, Destroy | the main path under `set -eu` | contract | D7 |
| 003.setu-toarray-empty | ToArray | fills a `declare -a out=()` target under `set -eu` | contract | finding P9-F3 — `${ref@a}` on an unbound array aborted the caller |
| 003.setu-toarray-unset | ToArray | fills a `declare -a out` (declared, never assigned) target | contract | P9-F3 (the harder half) |
| 003.exotic-roundtrip | Add, Contains, Remove, Extract | `-e`, `-n`, `a]b`, `a[b`, `a$b`, `a\b`, `a'b`, `a"b` round-trip | representation | X-ECHO / G1-13 for the option-looking values, G2-01 for the removal half |
| 003.leak | Destroy | no `W_items` / `W_data` / `W_class` and no `W.Add` wrapper survives `delete` | contract | X-LEAK / G1-01 |
| 003.set-e-return | Remove | a member answering rc 1 returns control to the caller under `set -e` | contract | D7 / M7-T1 — proven by running the path, not by auditing `&&` lists |
| 003.readme-sorted | ToArray + `TArray.sort` | the README's sorted-iteration example, end to end: `RESULT` 5 and byte order `apple banana cherry fig pear` | contract | **P4, invented.** `TSortedSet`/`TSortedHashSet` are wontfix and the documented replacement is "sort at the boundary", so the documented composition is executed here — the README cannot drift from `thashset` + `tarray` |

## 004_ReviewP2.sh — the 2026-09-06 review regressions — 11 cases

Every row is a finding fence: the case exists because the behaviour was once
wrong. All are `contract` class; the Basis is the finding.

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.outname-local | ToArray | the unit's own local name (`__ts_*`) → rc 2, set untouched | contract | G2-02 — such a name used to **alias** the working nameref |
| 004.outname-storage | ToArray | the instance's own `${inst}_items` → rc 2 | contract | G2-02 |
| 004.outname-malformed | ToArray | empty, `bad name`, `1abc`, `a-b`, `RESULT`, `IFS`, `__kk_x` → rc 2, silent | contract | kcl §1.2/§1.7 + G2-02; rc 2 = a malformed **call** (owner decision 2026-09-07) |
| 004.outname-assoc | ToArray | an associative target → rc 2, target untouched | contract | G2-02 — an assoc cannot receive an index-ordered fill |
| 004.outname-ok | ToArray | a valid name is still filled and `RESULT` is the count | contract | regression fence for the four rows above |
| 004.assign-queue | Assign | a `TQueue` that merely owns an `_items` array is refused | contract | G2-04 / R5 — the old `declare -p ${1}_items` probe accepted it and rewrote the storage with un-prefixed subscripts |
| 004.assign-plain | Assign | a plain variable that looks like an instance is refused | contract | G2-04 / R5 |
| 004.assign-ok | Assign | a real `THashSet` still copies | contract | regression fence |
| 004.foreach-dangling | ForEach | a dangling callback is refused up front — nothing runs | contract | G2-05 — it used to fail once per element |
| 004.foreach-empty | ForEach | an empty callback name is refused | contract | G2-05 |
| 004.foreach-ok | ForEach | a real callback still visits every element | contract | regression fence |

## 005_SetAlgebra.sh — the set algebra and both AddRange forms (P2) — 45 cases

### §A — the FPC parity oracle (FPC-TRACEABLE, 5 cases)

`Test_Set_General` is ported step for step. Two mappings were needed, both
recorded in the ledger: `T.Create(NumbersA)` (the copy ctor, :2359) → `C.Assign
A`, and `NumbersC.AddRange(NumbersB)` (:117, :146 — the `TEnumerable` overload
:2397, a whole **set** as the source) → `C.AddRange` over B's elements from
`ToArray` for the Boolean half plus `C.UnionWith B` for the membership half,
since our `AddRange` surface is varargs.

| ID | Members | Case | Class | Basis (seed line) |
|---|---|---|---|---|
| 005.seed-96 | Add, Contains, Count | A = {0,2,4,6,8}, B = {1,3,5,7,9}; every `Add` is True | behavior | seed :96–103 |
| 005.seed-106 | Assign, UnionWith, Add, AddRange, Count | C := copy(A); C ∪ B = {0..9}; `Add(5)` False; `AddRange(6,7)` False; Count 10 | behavior | seed :106–111 |
| 005.seed-114 | ExceptWith, AddRange, Count | C ∖ B = {0,2,4,6,8}; `AddRange(B)` True → {0..9} | behavior | seed :114–118 |
| 005.seed-121 | Clear, AddRange, SymmetricExceptWith | {0..5} ⊕ {3..9} = {0,1,2,6,7,8,9} | behavior | seed :121–135 |
| 005.seed-138 | Clear, AddRange, Assign, IntersectWith | {0..5} ∩ {3..9} = {3,4,5} | behavior | seed :138–148 |

### §B — hand-computed truth tables over every operand shape (4 cases)

Each case runs one member over the same eight shapes — empty/empty,
empty/non-empty, non-empty/empty, disjoint, overlapping, subset, superset, and
two instances with equal content — asserts the result set exactly (count **and**
membership) and asserts the **operand's storage is byte-identical afterwards**
(`declare -p`, not `Count`).

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 005.union-shapes | UnionWith | 8 shapes correct, operand untouched | behavior | FPC :2417 + a hand-computed table |
| 005.intersect-shapes | IntersectWith | 8 shapes correct, operand untouched | behavior | FPC :2425 (two-pass over self) |
| 005.except-shapes | ExceptWith | 8 shapes correct, operand untouched | behavior | FPC :2442 |
| 005.symex-shapes | SymmetricExceptWith | 8 shapes correct, operand untouched | behavior | FPC :2450 (two-pass over the operand) |

### §C — self-operation edges (4 cases)

Defined **because** every operation snapshots the operand's keys before this set
is touched; upstream these walk a live table while mutating it.

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 005.self-union | UnionWith | `a.UnionWith a` = a, rc 0 | boundary | S8 — every `Add` is a duplicate (:2417) |
| 005.self-intersect | IntersectWith | `a.IntersectWith a` = a | boundary | S8 — pass 1 of :2425 collects nothing, so it is a defined no-op |
| 005.self-except | ExceptWith | `a.ExceptWith a` = ∅ (full drain) | boundary | S8 — :2442 removes every element of the operand, and the operand is self |
| 005.self-symex | SymmetricExceptWith | `a.SymmetricExceptWith a` = ∅ | boundary | S3 — :2450 marks everything in pass 1, removes it in pass 2 |

### §D — exotic elements through every algebra path (5 cases)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 005.union-exotic | UnionWith | 12 exotic elements stay distinct and byte-exact | representation | inputs are the oracle |
| 005.intersect-exotic | IntersectWith | same, through the two-pass removal | representation | inputs are the oracle |
| 005.except-exotic | ExceptWith | same — the G2-01 `unset` idiom exercised **through** an algebra op | representation | G2-01 |
| 005.symex-exotic | SymmetricExceptWith | same, across both passes | representation | G2-01 |
| 005.no-exec-algebra | all four | no algebra path ever **executes** an element (canary file) | representation | G2-01 (the injection half) |

### §E — AddRange, the FPC AND-fold (7 cases)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 005.addrange-all-new | AddRange | every item new → rc 0 | behavior | FPC :2379 `Result := True; … Add(i) and Result` |
| 005.addrange-dup | AddRange | one item already present → rc 1, **and the new ones still land** | behavior | :2383–2385 — the `and` is on the right of the assignment, so nothing is short-circuited |
| 005.addrange-silent | AddRange | rc 1 with no stderr, even under `VERBOSE_KKLASS=debug` | contract | kcl §1.2 — rc 1 here is an answer, not an error |
| 005.addrange-inner-dup | AddRange | a duplicate **inside** the argument list makes it rc 1 | behavior | the fold sees the second occurrence as already present |
| 005.addrange-zero | AddRange | zero arguments → rc 0 | boundary | `Result := True` over an empty `array of T` (:2383) |
| 005.addrange-order | AddRange | the resulting set does not depend on argument order | behavior | set semantics; no external oracle needed |
| 005.addrange-exotic | AddRange | exotic elements stored byte-exact | representation | inputs are the oracle |

### §F — AddRangeFromArray, the bash-only bulk sibling (10 cases)

Not in FPC: FPC's collection overloads (:2388/:2397/:2407) take an enumerable,
which has no bash shape. The input **name** is validated through the same
helper as an output name (the `tinifile` `SetStrings` precedent), so a malformed
call is rc 2.

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 005.arfa-fill | AddRangeFromArray | fills from a caller indexed array → rc 0 | contract | bash extra; the Boolean is the same AND-fold |
| 005.arfa-sparse | AddRangeFromArray | a **sparse** array contributes only its surviving elements | boundary | holes are not elements; no FPC analog |
| 005.arfa-empty | AddRangeFromArray | an empty array → rc 0 and no change | boundary | mirrors `AddRange` with zero arguments |
| 005.arfa-dup | AddRangeFromArray | an already-present element → rc 1 | behavior | AND-fold, same as `AddRange` |
| 005.arfa-badname | AddRangeFromArray | a reserved or malformed input name → **rc 2**, set untouched | contract | kcl §1.2/§1.7 |
| 005.arfa-assoc | AddRangeFromArray | an **associative** array → rc 2 | contract | an assoc has no index order to read |
| 005.arfa-scalar | AddRangeFromArray | a plain (non-array) variable → rc 2 | contract | kcl §1.2 |
| 005.arfa-unset | AddRangeFromArray | an **unset** variable → rc 2 and no `set -eu` abort | contract | the P9-F3 shape (`local -; set +u` around `${ref@a}`) |
| 005.arfa-debug | AddRangeFromArray | the rejection is explained under `VERBOSE_KKLASS=debug` | contract | decision D2 |
| 005.arfa-exotic | AddRangeFromArray | exotic elements carried byte-exact | representation | inputs are the oracle |

### §G — operand validation: rc 1, atomic, debug-logged (6 cases)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 005.operand-missing | the four algebra ops | a missing operand → rc 1 and nothing changes | contract | R5 + PLAN §6.4 atomicity |
| 005.operand-string | the four algebra ops | a plain string operand → rc 1 and nothing changes | contract | R5 |
| 005.operand-queue | the four algebra ops | a `TQueue` that merely owns an `_items` array → rc 1 | contract | R5 / G2-04 — the **class** decides, not the presence of storage |
| 005.operand-debug | the four algebra ops | a rejected operand produces a debug line under the switch | contract | decision D2 |
| 005.operand-silent | the four algebra ops | with the switch off the rejection is completely silent | contract | kcl §1.2 |
| 005.operand-nonident | the four ops + Assign | 8 non-identifier shapes × 5 members = 40 rejections, each rc 1 with **empty stderr** and the set intact | contract | finding **P2-F1** — `${!name_class}` on a non-identifier made bash print `invalid variable name` |

### §H/§I/§J — surface, forks, relative performance (4 cases)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 005.no-sentinel | all 17 methods | no public member answers with `__ths_pending__` | contract | the stub-removal fence (`Notify` included since P3) |
| 005.fork-six | the six P2 members | `$BASHPID` unchanged across the sequence | contract | kcl §1.6 |
| 005.path-empty | the six P2 members | the right answers under `PATH=''` | contract | kcl §1.6 |
| 005.perf-gate | UnionWith, IntersectWith | 1k×1k costs at most **3×** a 1k `Add` loop | contract | kcl §1.8 relative gate (a *relative* limit — no hard-ms assert, which flakes under sweep load) |

## 006_Events.sh — the event seam (P3) — 55 cases

### §A — the FPC notification oracle (FPC-TRACEABLE, 9 cases)

`Test_TCustomSet_Notification` :261–338 is ported step for step. Its `LSet`
deliberately carries **no** listener, which also pins that events belong to the
receiver and not to the operand; its two `EnumerableStrings*` `AddRange`
overloads (:277/:278) map to our varargs `AddRange`, as at P2.

| ID | Members | Case | Class | Basis (seed line) |
|---|---|---|---|---|
| 006.seed-274 | onNotify, Add, AddRange | `Add` + 3 × `AddRange` fire `added` seven times, in call order | event | seed :274–279 |
| 006.seed-282 | Remove, Extract | `cnRemoved` then `cnExtracted` | event | seed :282–286 |
| 006.seed-289 | ExceptWith | `removed` for the hit only | event | seed :289–292 |
| 006.seed-295 | IntersectWith | `removed` for the victims only | event | seed :295–298 |
| 006.seed-301 | SymmetricExceptWith | `added` (pass 1) before `removed` (pass 2) | event | seed :301–306 |
| 006.seed-309 | Remove, Extract | a second removal/extraction pair | event | seed :309–313 |
| 006.seed-316 | UnionWith | `added` for the new element | event | seed :316–320 |
| 006.seed-323 | Remove, Clear | `Clear` fires `removed` for what is left | event | seed :323–328 |
| 006.seed-330 | Add, Destroy | `Add` then `Free` → `cnAdded` then `cnRemoved` | event | seed :330–336 — the S5 proof |

### §B — per-member sequences, one case per S-pin (11 cases)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 006.s1-add | Add | new → exactly one `added`; duplicate → **no** event and no mutation | event | S1 — FPC :2559 guards the write |
| 006.s2-after | Remove | the `removed` callback already sees `Contains` false and `Count` decremented | event | S2 — :2566 calls `DoRemove` after the bucket is found; the port unsets first |
| 006.s2-miss | Remove | a miss fires nothing | event | S2 — :2572 `if Result then` |
| 006.s6-extract | Extract | hit → one `extracted` after the removal; miss → nothing | event | S6 — :2582 exits before `DoRemove` |
| 006.extract-result | Extract | `RESULT` survives a callback that clobbers `RESULT` | contract | bash-side: `kk._return` runs **after** the event (the kklass func contract) |
| 006.s4-clear-first | Clear | the storage is emptied first — the very first callback sees `Count` 0 | event | S4 — :2588 delegates to the dictionary's `Clear`, which releases first and notifies after |
| 006.s4-clear-empty | Clear | clearing an empty set fires nothing | event | S4 |
| 006.s5-delete-hookless | Destroy | with no listener, `delete` fires nothing and still frees the storage | event | S5 + the gate (:2530 `else nil`) |
| 006.s5-delete-hooked | Destroy | with a listener, `delete` fires one `removed` per element | event | S5 — :2554 frees the internal dictionary, whose `Clear` notifies |
| 006.assign-phases | Assign | every `removed` (old contents) is **strictly before** every `added` (new), asserted by index | event | bash-side composition of `Clear` + `Add`; no FPC analog (`Create(ACollection)` starts empty) |
| 006.addrange-events | AddRange, AddRangeFromArray | `added` for the genuinely new only, in **argument order** (exact compare) | event | :2379 fold order |

### §C — the algebra ops as event multisets (8 cases)

Compared as multisets against the §B truth table A={a,b,c,d}, B={c,d,e,f},
because the within-phase order is hash order.

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 006.union-events | UnionWith | `added` for the operand-only elements | event | :2417 |
| 006.intersect-events | IntersectWith | `removed` for the victims only | event | :2425 |
| 006.except-events | ExceptWith | `removed` for the hits only | event | :2442 |
| 006.symex-events | SymmetricExceptWith | every `added` (pass 1) strictly before every `removed` (pass 2) | event | :2450 — the phase order is deterministic even though the within-phase order is not; the seed :303–304 expects the same |
| 006.self-noop-events | UnionWith, IntersectWith | `a ∪ a` and `a ∩ a` fire **nothing** | boundary | S8 — no element changes state |
| 006.self-except-events | ExceptWith | `a ∖ a` fires `removed` × \|a\| | boundary | S8 |
| 006.self-symex-events | SymmetricExceptWith | `a ⊕ a` fires `removed` × \|a\| | boundary | S3 |
| 006.operand-silence | the four algebra ops | an **empty** operand fires nothing, and a **rejected** operand fires nothing | boundary | validation happens before any mutation, so there is nothing to notify |

### §D — the callback signature, byte-exact (3 cases)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 006.sig-exotic | AddRange | `cb <inst> <item> <action>` byte-exact for 12 exotic elements (`''`, `]`, `[`, `a]b`, newline, `$(touch canary)`, `*`, `it's`, `a\b`, `k`, `kk`, `café`), with a canary proving nothing is executed | event | ported from `InternalDictionaryNotify` :2500 — the sender is the **set** |
| 006.sig-clear | Clear | the same 12 come back through `Clear`'s `removed` events | event | :2500 + S4 |
| 006.sig-empty-k | Remove, Extract | the `''` element and `k` / `kk` fire distinctly | representation | the `k`-prefix idiom must not collide in the event stream either |

### §E — mutating and re-entrant callbacks (4 cases)

Callbacks run **after** the mutation and every loop walks a snapshot, so a
mutating callback leaves the set consistent. The invariant asserted is the full
one: `Count` == raw storage subscript count == `ToArray` count. Terminating the
recursion is the callback's job — documented in the README.

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 006.reentrant-clear | Clear + Add in the callback | add-during-`Clear` → 3 `removed` + 1 `added`, set = {REBORN}, invariant holds | contract | defined here; FPC enumeration over mutation is UB |
| 006.reentrant-union | UnionWith + Remove in the callback | remove-during-`UnionWith` → `c:added d:added a:removed`, set = {b,c,d} | contract | the operand snapshot is what makes it defined |
| 006.reentrant-add | Add + Clear in the callback | `Clear`-during-`Add` → `zz:added zz:removed`, set empty | contract | events fire after the write |
| 006.reentrant-depth | Add | a bounded 5-deep recursion terminates: 5 `added`, 5 elements | contract | re-entrancy is allowed, not guarded — the guard is the callback's |

### §F — robustness of the dispatch (6 cases)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 006.dangling | Notify | a callback name that is not a function: the mutation still happens, rc 0, silent | contract | the name is resolved with `declare -F` at **fire time**; FPC method pointers cannot dangle |
| 006.dangling-debug | Notify | exactly one `kk.debug` line **per event** under the switch | contract | decision D2 |
| 006.cb-rc | Notify | the callback's exit status is **ignored** | contract | a Pascal event is a `procedure` and returns nothing |
| 006.cb-seteu | Notify | a failing callback does not abort a `set -eu` script (proved in a child bash) | contract | D7 |
| 006.detach | on_notify | detaching mid-life stops the events | contract | `SetOnNotify(nil)` :2530 unhooks the dictionary |
| 006.sender | Notify | the first callback argument is the **instance handle** | event | `InternalDictionaryNotify` :2500 passes `Self` — the set, not the storage |

### §G — the virtual seam and `_notifyHook` (5 cases)

No FPC counterpart: a set there has no `Notify` at all (`OnNotify` :526 is a
property over the abstract pair :495/:496). The seam is the house pattern of
`tqueuestack`/`tdictionary`, chosen in PLAN §2.4.

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 006.hook-exists | _notifyHook | a fresh set exposes it and it starts empty, like `on_notify` | contract | house surface |
| 006.subclass | Notify (overridden) | a descendant that overrides `Notify` receives events with **no** `on_notify` set | event | the `TObjectDictionary` pattern (`tdictionary.sh:628`) |
| 006.subclass-both | Notify (overridden) | with a user callback attached too, the override's `inherited` body runs **first** | event | the `tqueuestack` ordering rule (the callback observes the pre-free state there) |
| 006.subclass-delete | Destroy | the subclass also gets one `removed` per element on `delete` | event | S5 through the seam — `Destroy` calls `$this.Clear`, the virtual call |
| 006.gate-blocks | Notify (overridden) | an override whose `_notifyHook` is cleared and with no `on_notify` gets **nothing** | contract | the gate `[[ -n $on_notify \|\| -n $_notifyHook ]]` is parity with :2530's `else nil` |

### §H — the `onNotify` validating setter (5 cases)

FPC's `SetOnNotify` cannot validate — a Pascal method pointer either compiles or
does not — so the whole member is bash-side.

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 006.onnotify-set | onNotify | a real function name → rc 0 and the events start | contract | :2530 analog |
| 006.onnotify-bad | onNotify | a name that is not a function → **rc 2**, the installed hook **unchanged** | contract | kcl §1.2 (a malformed call), owner decision at P3 over rc 1 |
| 006.onnotify-debug | onNotify | the rejection is explained under `VERBOSE_KKLASS=debug` | contract | decision D2 |
| 006.onnotify-clear | onNotify | `''` detaches, rc 0, and the events stop | contract | :2530's `else nil` branch |
| 006.onnotify-var | on_notify | the direct house spelling `s.on_notify = "cb"` keeps working alongside the setter | contract | the property is a plain writable var (kklass) |

### §I — surface, forks, cost (4 cases)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 006.no-sentinel | all 17 methods | no public member — `Notify` included — answers with `__ths_pending__` | contract | the stub-removal fence; `TSet._pending` was deleted at P3 |
| 006.fork | the event path | `$BASHPID` unchanged with a listener attached | contract | kcl §1.6 |
| 006.path-empty | the event path | a full hooked sequence runs under `PATH=''` | contract | kcl §1.6 |
| 006.cost | Add | 1k `Add` with a listener stays inside **5×** the unhooked loop | contract | a *relative* gate against its own baseline (no hard-ms assert); the published numbers are in `bench.sh` / README |

---

## Class breakdown

| Class | Rows |
|---|---|
| contract | 73 |
| event | 29 |
| behavior | 20 |
| representation | 15 |
| boundary | 12 |
| **total** | **149** |

**14 rows are FPC-traceable in the strict sense** — they cite a seed procedure
line rather than an argument: `005` §A (5, `Test_Set_General` :96–148) and
`006` §A (9, `Test_TCustomSet_Notification` :274–336). Everything else is
invented or source-pinned and carries its own Basis; the `behavior` rows quote
the implementation line they were read from, which is the next best thing to a
seed.

## Deliberately NOT covered (documented elsewhere)

- **Comparer and capacity** (`Create(IEqualityComparer)` :562, `Capacity` :523,
  `TrimExcess` :524) — wontfix, ledger `out_of_scope`; `declare -A` is the hash
  table. There is no negative test: the members simply do not exist, which
  `005`/`006` §H/§I already prove by sweeping the whole surface.
- **`TSortedSet` / `TSortedHashSet` / the AVL family** (:839 / :883 / :812) —
  wontfix. The replacement *is* tested: `003.readme-sorted` runs
  `ToArray` + `TArray.sort`.
- **Enumerator objects** (:480–489, :537–552) — wontfix; `ForEach` and `ToArray`
  carry the coverage.
- **NUL bytes in elements** — a bash language limit, untestable.
- **Hard-ms performance assertions** — house lesson: they flake under sweep
  load. Both performance cases (`005.perf-gate`, `006.cost`) are **relative** to
  a baseline measured in the same process; the honest absolute numbers live in
  `bench.sh` and are published in the README.

## Test-side traps pinned during this effort (also PLAN.md §6)

- **`$( )` around a mutating call mutates only the subshell copy.** Capture
  stderr with a file redirect, never with command substitution.
- **A `func` PRINTS inside any subshell.** `Count`, `Extract` and `ToArray`
  echo their value whenever `BASH_SUBSHELL > 0`, so a `PATH=''` probe wrapped in
  `$( )` must redirect every `func` call to `/dev/null` and read `RESULT` — the
  `005` §I shape, repeated in `bench.sh`.
- **`unset` re-parses a double-quoted subscript** (G2-01). The idiom is
  `pk="k$item"; unset 'ref[$pk]'` — single quotes — and a test must remove and
  extract exotic elements, not merely add and find them.
- **Never edit the unit while a sweep is in flight.**
