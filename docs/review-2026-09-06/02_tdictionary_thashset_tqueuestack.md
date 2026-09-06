# Reviewer report G2 — tdictionary / thashset / tqueuestack (2026-09-06)

Repro scripts: `repro/g2/p1_unset.sh … p5_misc.sh`.

### Summary
All three suites are green on both bashes (5.2.37 and 5.3.9): tdictionary 130/130, thashset 23/23, tqueuestack 76/76. tdictionary is in good shape — every exotic key (`''`, `]`, `[`, `*`, quotes, backslash, `$(…)`, backtick, newline, `k`/`kk`) round-trips through every mutating path, ownership matches FPC (cnRemoved frees, cnExtracted does not, failed Add frees nothing), and no forks in any method. tqueuestack is correct under a 4000-op random fuzz against a reference (crossing compaction), ownership/quirks are FPC-exact, but `ToArray` has no output-name validation and corrupts its own storage on a reserved name. thashset (WIP, P1) has a **HIGH** defect: its `unset "…[$pk]"` is double-quoted (not the single-quoted tdictionary idiom the PLAN/ledger claim it reuses "verbatim"), so `Remove`/`Extract` silently fail for items containing `]`, `[`, quotes, `\`, `$`, backtick, AND execute `$(…)`/backtick content in the item (code injection).

### Findings

`G2-01 | HIGH | thashset | thashset.sh:166, :188 | Remove/Extract use double-quoted unset → silent non-removal + command injection`
`unset "${__inst__}_items[$__ts_pk]"` lets `unset` re-expand the subscript. Items containing `]`, `[`, `'`, `"`, `\`, `$…` or backticks are NOT removed while rc=0 / RESULT=item are returned; `$(…)` / backtick content is executed.
Repro (`p2_hashset_api.sh`, 5.2 and 5.3): `H.Add ']' ; H.Remove ']'` → rc 0 but `H.Contains ']'` rc 0 and Count 1. `H.Add '$(touch pwned.txt)'; H.Remove '$(touch pwned.txt)'` → file created. Same for `Extract`.
Expected: element removed, no execution (tdictionary `pk="k$key"; unset 'items_ref[$pk]'` passes all 15 keys). tdictionary and tqueuestack (numeric subscript) are NOT affected (`p1_unset.sh`, `p4_tdict.sh`).
Fix: `unset '__ts_it[$__ts_pk]'` (single-quoted, nameref) exactly as tdictionary.sh:223/270; add Remove/Extract of exotic items to tests/002 (currently only Add/Contains/ToArray are exercised on exotic items — that is why 23/23 is green).

`G2-02 | MED | tqueuestack | tqueuestack.sh:172-181 (_toArray) | ToArray has no output-name validation: reserved name doubles the storage, bad names rc 0`
`q.ToArray __tqs_it` → `local -n __tqs_out=__tqs_it` aliases the storage; the loop appends the array to itself: Count goes 2→4 (queue and stack both, rc 0). `q.ToArray ""` / `"bad name"` → bash error on stderr, then a throwaway local is filled, rc 0, RESULT=count. An assoc array as target → garbage keys, rc 0.
Repro: `p3_tqs.sh`, `p5_misc.sh`. Expected: rc 1, storage untouched (tdictionary.sh:393 validates with `[[ -z ]] || ! declare -n … 2>/dev/null → return 1`).
Fix: `[[ -z $1 || $1 == __tqs_* ]] && return 1; declare -n __tqs_out="$1" 2>/dev/null || return 1` (same for thashset.sh:217 `ToArray`, which has the identical shape with `__ts_*`).

`G2-03 | MED | cross-unit (kklass) | kklass/kklass.sh:99 (kk._return) | echo -n eats func values that look like echo options under $()`
`$(d.GetItem k)`, `$(q.Peek)`, `$(s.Pop)`, `$(h.Extract x)` return `''` when the stored value is `-n`, `-e`, `-E`, `-neE`… Direct-call + `$RESULT` is correct.
Repro: `p5_misc.sh`: `Q.Enqueue -e; v="$(Q.Peek)"` → `captured=[] direct=[-e]`. README of tdictionary advertises the `$()` form.
Fix (kklass): `printf '%s' "$return_value"`.

`G2-04 | MED | thashset | thashset.sh:113-114 (_isSet), :246 | Assign accepts any instance that has a `_items` variable; a non-set corrupts storage`
`_isSet` only checks `declare -p ${1}_items`. `A.Assign Q` (TQueue) → rc 0, storage becomes `([0]=1 [1]=1)` — keys without the `k` prefix, so `Contains 0` is a miss and `ToArray` yields `1 0`. `A.Assign D` (TDictionary) rc 0 (keys copied, plausible but undocumented). PLAN §2.3 says "validated via its storage `@a` check".
Fix: `[[ ${ref@a} == *A* ]]` like tdictionary.sh:315, plus class check (decision R5).

`G2-05 | LOW | thashset | thashset.sh:231-238 (ForEach) | callback not validated`
`F.ForEach no_such_cb` / `F.ForEach ""` → "command not found" once per element, rc 0. tdictionary.sh:481 validates with `declare -F` and returns 1.

`G2-06 | LOW | thashset | thashset.sh:17-23 header, PLAN.md conventions line, thashset_ledger.json design_decisions.storage | docs claim "single-quoted unset … idioms REUSED verbatim"` — code contradicts (G2-01).

`G2-07 | LOW | tdictionary | tdictionary.sh:40-41 header; README.md:122-123; docs/TDictionary.md ("function results → echo + RESULT") | contract drift vs kklass D1 (direct call is silent)`
Direct `D.GetItem a >&3` writes 0 bytes; value is echoed only inside `$()`. Tests (004.getitem-forms) are consistent with the real contract; only prose is stale.

`G2-08 | LOW | tdictionary | tdictionary.sh:6-7 | redundant `source klib.sh`/`kerr.sh`` — kklass.sh:5-6 already sources both; tdictionary uses neither.

`G2-09 | LOW | tdictionary | tdictionary.sh:266-276 | `RESULT_KEY` is a global side channel that outlives the call` — documented; namespace pollution only.

`G2-10 | LOW | tqueuestack + tdictionary | tqueuestack.sh:251-258 vs tdictionary.sh:558-561 | inconsistent state after a rejected ctor token`
`TObjectQueue.new q bogus` → rc 1 but the instance exists and OWNS (test 001 pins it); `TObjectDictionary.new d bogus` → rc 1 and the instance exists NON-owning. Both leave a live instance whose `.delete` cleans up. (Decision R3: instance with defaults + rc 1 in both.)

Reproduced non-findings: tdictionary 15-key exotic torture through Add/AddOrSetValue/SetItem/GetItem/TryGetValue/ExtractPair/Remove/Clear-with-hooks/Assign/ForEach all byte-exact; nameref subscripts are single-expanded on 5.2 and 5.3; TObjectQueue.Dequeue leaves RESULT untouched and passes rc; TObjectStack.Pop returns the dead handle; tqueuestack fuzz 4000 mixed ops = reference, ToArray order exact; `set -e` smoke passes for all three; all per-instance arrays (`_items`, `_qhead`, `_nhook`) are unset by the destructors; zero `$(…)`/pipes in any method body. `TObjectDictionary.AddOrSetValue k sameHandle` frees the handle and keeps the dead name (FPC SetValue does the same — parity, decision R4).

### Test gaps
- thashset/002: no Remove/Extract on exotic items (the exact hole hiding G2-01); no Assign from a non-THashSet instance that has `_items`; no ForEach with a dangling callback.
- tqueuestack: no ToArray negative cases (empty/invalid/reserved name/assoc target); no test that a Notify callback which mutates the collection terminates/keeps invariants; no owning-`Clear` with a callback that re-pushes the freed handle.
- tdictionary: no negative test for values `-n`/`-e` via `$()`; no test that `Assign` from a THashSet/other `_items`-bearing non-dictionary is rejected; no test for `AddOrSetValue k sameOwnedHandle`.
- All three: `$()`-path coverage of Count/count only for numbers; no test that a callback named `inst.method` (dotted name) dispatches.
