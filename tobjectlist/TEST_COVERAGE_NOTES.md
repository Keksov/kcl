# tobjectlist — test coverage notes

**Status: FINALIZED at P2 (2026-07-13).** Suite 001–003 = 31 cases, green on
bash 5.2.37 AND true 5.3.9. No bench (ownership adds one `declare -F` per
removed element — nothing worth measuring; PLAN §7).

Protocol (house): **invented** cases get a row here; **FPC-traceable** cases
(002_FpcParity.sh — the complete fpcunit suite
`packages/fcl-base/tests/utcobjectlist.pp`, mined verbatim) cite their FPC
procedure instead. Adaptations for bash: `TObject` instances → kklass
instances (`TList.new`); the `TMyObject(:TObject)` subclass →
`TStringList(:TList)` (same one-level-derived shape) for FindInstanceOf; the
`IsFreed` destructor flag → dispatcher liveness (`declare -F "$h.delete"`);
`L.Items[i]` → `L.Get i`. Classes: `contract` (rc/RESULT/guard/zero-fork),
`behavior` (ownership semantics), `torture` (hostile elements/sequences).

## 001 — ownership core (invented; P0)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 001.create | Create | count 0, owns true by default | behavior | FPC ctor default (also 002/TestCreate) |
| 001.token | Create | `false`/`true` honored; bogus → rc 1, list valid+owning | contract | house token convention (TStopwatch `startnew`) |
| 001.headline | destructor | owning delete frees; non-owning leaves alive | behavior | FPC Notify(lnDeleted) on destroy |
| 001.toggle | owns_objects | toggled mid-life → dtor honors current value | behavior | FPC OwnsObjects is writable |
| 001.guard | _free | non-instance / double-free / empty → silent rc-0 no-ops | contract | liveness guard (generalized nil.Free) |
| 001.mixed | destructor | live handle + plain strings + "" → clean delete | torture | guard under mixed content |
| 001.surface | inherited TList | Add/Get/IndexOf/Sort/First/Last work on handles | contract | inheritance sanity |
| 001.empty | destructor | empty owning list deletes cleanly | behavior | boundary |
| 001.zero-fork | ctor/dtor | full owning cycle under `PATH=''` | contract | builtins only |

## 002 — FPC parity (FPC-TRACEABLE; utcobjectlist.pp)

| ID | Members | Case | Basis (FPC proc) |
|---|---|---|---|
| 002.create | Create | count 0; OwnsObjects true default | TObjectList_TestCreate |
| 002.add | Add/Get | counts 1→2; Items[0]=O1, Items[1]=O2 | TObjectList_TestAdd |
| 002.extract | Extract | returns O1; count 1; first O2; O1 alive | TObjectList_TestExtract |
| 002.remove | Remove | count 1; first O2 (O1 alive — non-owning) | TObjectList_TestRemove |
| 002.indexof | IndexOf | O1→0, O2→1, non-added→−1 | TObjectList_TestIndexOf |
| 002.findinstanceof | FindInstanceOf | exact/inexact over base+derived pair (+is-a from startAt 1) | TObjectList_TestFindInstanceOf |
| 002.insert | Insert/Get | count 3; [1]=O3, [2]=O2 | TObjectList_TestInsert |
| 002.firstlast | First/Last | O1 / O2 | TObjectList_TestFirstLast |
| 002.ownsobjects | destructor | Create(True)+Add+Free → element freed | TObjectList_TestOwnsObjects |

## 003 — ownership torture (invented)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.delete | Delete | owning frees victim only; non-owning frees nothing | behavior | lnDeleted on Delete |
| 003.delete-oob | Delete | out-of-bounds (±) → rc 1, NOTHING freed | contract | bounds-before-free discipline |
| 003.remove | Remove | hit frees (idx); miss alive (−1) | behavior | lnDeleted via Remove |
| 003.put | Put | replace frees OLD; same handle NOT freed; oob frees nothing | behavior | FPC TList.Put pointer-change rule |
| 003.batchdelete | BatchDelete | frees exactly the clamped range | behavior | bash extra = removal path |
| 003.duplicate | Clear | same handle twice → freed once, rc 0 | torture | guard vs double-free |
| 003.mixed | Clear | live + plain string + dead handle + "" → clean | torture | guard under mixed content |
| 003.toggle | Delete | owns false→alive, true→freed (mid-life) | behavior | writable OwnsObjects |
| 003.extract-survives | Extract+dtor | extracted element survives list.delete | behavior | lnExtracted releases ownership |
| 003.fio-edges | FindInstanceOf | class-name STRING element skipped; empty arg → rc 2 | contract | liveness guard + arg validation |
| 003.dtor-many | destructor | 5 owned elements all freed | behavior | dtor loop |
| 003.zero-fork | all removal paths | Delete/Extract/FindInstanceOf/Clear cycle under `PATH=''` | contract | builtins only |

## 004–005 — kcl contract + review 2026-09-06 (invented; P1/P2)

`004_Contract.sh` is the house contract file (identical in shape across the 17
kcl suites); `005_ReviewP2.sh` closes the review findings of phase P2.

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.setu | source, main path | loads and re-loads under `set -eu`, main path clean | contract | kcl README §1.4 (D7) |
| 004.inj | Delete/Put/BatchDelete/FindInstanceOf | injection-shaped index rejected, nothing executed | contract | kcl README §1.5 (D1, G1-02) |
| 004.leak | destructor | no `W_items`/`W_data`/`W_class`/wrapper after `.delete` | contract | kcl README §1.9 (G1-01) |
| 004.set-e | Delete | a failing member returns control under `set -e` | contract | D7 |
| 005.dtor-storage | Destroy | `${inst}_items` gone after delete, owning AND non-owning | contract | G1-01 (`inherited` in Destroy) |
| 005.count-shrink | _setCount | owning shrink frees the dropped tail; non-owning does not; growth frees nothing | behavior | FPC SetCount → Delete → Notify(lnDeleted) (G1-07a) |
| 005.capacity-guard | _setCapacity | `capacity < count` → rc 1, nothing dropped or freed | contract | FPC EListError / decision R2 (G1-07b, G1-09) |
| 005.assign-atomic | Assign | the unimplemented stub leaves an owning list untouched | contract | G1-07c (it used to Clear first, freeing everything) |
| 005.owns-token | owns_objects | `yes` → rc 2 and the value unchanged; `true`/`false` still work; a rejected token does not disown | contract | FPC Boolean property / G1-16 |
| 005.fio-token | FindInstanceOf | a non-boolean `exact` token → rc 2 (was silently `true`) | contract | G1-16 |
