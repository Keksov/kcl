# tdictionary — test coverage notes (non-FPC cases)

Protocol (same as dateutils/math): every test case **not traceable to an FPC test file**
gets a row here: where it lives, what it checks, why FPC lacks it, and the basis for the
expected value. Classes: `boundary` (edge FPC never exercises), `bash-convention` (bash-side
API shape: rc mapping, RESULT, lifecycle), `representation` (bash storage/string
specifics), `cross-check` (internal consistency, no external oracle needed).

FPC seeds used for traceable cases (no rows needed): `packages/rtl-generics/tests/`
`tests.generics.dictionary2.pas` — TTestGenDictionary add-method matrix (TestAdd incl.
duplicate-raises, TestTryAdd, TestAddOrSet, TestAddModify, DoTestRemove);
`tests.generics.dictionary.pas` — TestKeys + notification tests (used from P3/P5).
Implementation line refs are into `src/inc/generics.dictionaries.inc`.

## P0 — scaffolding & storage (001, 002)

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 001.create/count/storage | Create, count | fresh instance: count 0, storage is `declare -A` and empty | bash-convention | kklass instance lifecycle; FPC ctor has no bash-observable analog |
| 001.ctor-arg | Create | `TDictionary.new d 1000` → rc 0, arg IGNORED | bash-convention | API v2 owner decision (capacity family dropped); FPC would presize |
| 001.capacity-absent | (capacity) | `d.capacity` fails — member not ported | bash-convention | API v2 wontfix (negative test pins the drop) |
| 001.computed-count | count | direct-seed 2 storage entries → count 2 | cross-check | count ≡ `${#items[@]}` by design; proves no stored mirror |
| 001.lifecycle | Destroy | delete → inaccessible; `${inst}_items` unset; recreate same name | bash-convention | kklass `.delete` + destructor contract |
| 002.* (all 10) | storage idioms | 34-key torture: `''`, `]`, `[`, `a]b[c`, braces, `*`, `?`, `[a-z]`, punctuation, space, newline, tab, quotes, backslash, `$(echo pwned)`, backtick, `$HOME`, `${PATH}`, `k`/`kk`, unicode — store/exists/fetch/delete, prefix round-trip `${k#k}`, `''`/`k`/`kk` distinctness, empty-value vs missing, trailing-`\n` value, nameref cycle, zero-fork | representation | bash assoc-subscript semantics (5.2 rejects `['']`; unset double-expansion) — no FPC counterpart; expected values are the stored inputs themselves |

## P1 — core CRUD (003, 004, 005)

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 003.dup-no-mutation | Add | duplicate Add leaves value AND count unchanged | cross-check | seed asserts the raise only; no-mutation read from InternalDoAdd :399 (raise precedes any write) |
| 003.tryadd-silent | TryAdd | duplicate → rc 1 with NO stderr even outside debug mode | bash-convention | TryAdd returns False (an answer, not an exception) :718; rc-vs-exception mapping is bash-side |
| 003.empty-key | Add, GetItem | `''` as key: add, fetch, duplicate-reject | boundary | seeds use integer-derived keys only; validity of `''` from TKey=string semantics (impl treats keys opaquely) |
| 003.empty-value | Add, ContainsKey, GetItem | value `''` stored; key exists; fetch returns `''` | boundary | Default(TValue)-shaped value; distinguishability via ContainsKey per :742 |
| 003.glob-value | Add, GetItem | value `a * b ? [c] $(no)` byte-exact | representation | bash quoting/globbing hazard; expected = input |
| 004.getitem-forms | GetItem | `$()` capture vs direct call + `$RESULT` agree | bash-convention | kklass func return contract (kk._return echo-in-subshell) |
| 004.getitem-miss | GetItem | miss → rc 1, RESULT cleared to `''` (stale value not leaked) | boundary | EListError raise :640 mapped to rc; RESULT='' chosen to mirror TryGetValue's Default(TValue) :705; stale-leak guard is bash-specific (kklass restores caller RESULT on early return — fixed via explicit kk._return) |
| 004.setitem-miss | SetItem | miss → rc 1, NOTHING inserted (update-only) | boundary | SetItem :662 raises SItemNotFound — FPC ≠ Delphi divergence; seeds never write a missing key via Items[] |
| 004.trygetvalue-empty | TryGetValue | pair with `''` value: rc 0 + RESULT `''` (vs miss rc 1) | boundary | rc carries the boolean, not the value; :705 |
| 004.exotic-api | Add/ContainsKey/GetItem | `''`, `]`, `*`, `a b`, newline, `k` through the PUBLIC API | representation | P0 idioms re-validated at API level; expected = inputs |
| 004.trailing-nl | GetItem | `$'…\n\n'` value: RESULT exact, `$()` strips (documented) | bash-convention | bash command-substitution semantics |
| 005.remove-miss | Remove | absent / never-existed key → rc 0, silent, count stable | boundary | Remove :492 exits silently when FindBucketIndex < 0; seeds remove existing keys only |
| 005.readd | Add after Remove | re-Add removed key gets fresh value | cross-check | tombstone-artifact guard (bash storage has no tombstones; guards the design) |
| 005.remove-exotic | Remove | `''`, newline, `*` keys removed cleanly | representation | unset idiom at API level; expected from count arithmetic |
| 005.clear-usable | Clear, Add | Clear :515 empties; dict fully usable after | cross-check | Clear+add-after sequence; state re-derivable from ops |
| 005.interleave | mixed | 8-op interleaved sequence; final state == storage == expected map | cross-check | reference state computed by hand from the pinned per-op semantics |

## P2 — removal/query extras + bulk fill (006, 007, 008)

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 006.miss-default-pair | ExtractPair | miss → ('','') with rc 0, dict untouched, stale RESULT/RESULT_KEY not leaked | boundary | ExtractPair :503 `Exit(Default(TPair))` — seeds never extract a missing key |
| 006.empty-key-ambiguity | ExtractPair | ''-key hit shape == miss shape; ContainsKey-first disambiguation | boundary | Default(TKey)='' in FPC creates the SAME ambiguity; parity pinned |
| 006.exotic/trailing-nl | ExtractPair | newline/glob keys; `$'…\n\n'` value via RESULT | representation | inputs are the oracle |
| 006.subshell-caveat | ExtractPair | `$()` yields the value but removal stays in the subshell | bash-convention | bash command-substitution semantics; direct call = real extraction |
| 007.dup-values | ContainsValue | two keys, same value; found until the LAST holder is removed | cross-check | linear-scan semantics :750; seeds don't exercise duplicate values |
| 007.empty/multiline | ContainsValue | '' value found; multiline exact-match only (no substring) | boundary | default comparer = whole-string equality |
| 007.empty-dict | ContainsValue | empty dict → rc!=0 | boundary | :761 `Length(FItems)=0 -> False` |
| 007.getvaluedef-* | GetValueDef | present / present-'' / absent / absent-no-default | bash-convention | NOT in FPC TDictionary (convenience); existence decides, never rc!=0 |
| 008.assign-* | Assign | copy incl. exotic pairs; source intact; copies independent; empty-source empties; self-assign no-op; invalid source rc 1 untouched | bash-convention | Create(ACollection) analog :106-114; self-assign/invalid-source are bash-side contracts |
| 008.addpairs-odd | AddPairs | odd argc → rc 1, nothing added | bash-convention | argument-shape validation has no FPC analog |
| 008.addpairs-abort | AddPairs | duplicate aborts AT that pair (earlier stay, later unattempted; also within-batch repeat) | cross-check | mirrors FPC Create(collection) raise-aborts-loop shape :106-114 + :399 |

## P3 — iteration (009, 010)

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 009.dup-values | Values | duplicate value listed once per holder | cross-check | ValueCollection enumerates buckets, not a set; seed TestKeys covers keys only |
| 009.empty-echo | Keys, Values | empty dict → zero output lines (not one empty line) | bash-convention | line-oriented echo form is bash-side |
| 009.exotic-lossless | KeysToArray, ValuesToArray | newline/glob/empty keys and trailing-`\n` values round-trip via nameref | representation | inputs are the oracle; echo forms documented ambiguous |
| 009.toarrays-aligned | ToArrays | keys[i]→values[i] verified against GetItem | cross-check | pair integrity, no external oracle |
| 009.out-reset | *ToArray | pre-filled output array cleared before fill | bash-convention | nameref-fill contract |
| 009.out-validation | *ToArray, ToArrays | empty/invalid/same-name output vars → rc 1 | bash-convention | bash identifier rules; FPC returns fresh arrays |
| 010.snapshot-* | ForEach | delete-others (1 visit), delete-self (all visited), additions unvisited | bash-convention | snapshot semantics DEFINED here (FPC enumeration over mutation is UB — we pin a safe contract) |
| 010.cb-rc-ignored | ForEach | callback rc=7 does not abort; ForEach rc 0 | bash-convention | enumerator has no comparable channel in FPC |
| 010.zero-fork | ForEach | 50 callbacks under PATH='' | representation | fork-free goal |

## P5 — notifications (011, 012)

Seed-traceable (no rows): value-added on Add, value/key-removed on Remove and on
Free, overwrite = old-removed + new-added with key silent — ported from
tests.generics.dictionary.pas (TestValueNotification, TestValueNotificationDelete,
TestNotificationDelete, TestKeyValueNotificationSet).

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 011.no-hooks | all mutators | mutations with no callbacks: zero events, semantics intact | bash-convention | guard-off fast path is bash-side |
| 011.pair-order | Add/TryAdd | KeyNotify fires BEFORE ValueNotify | cross-check | PairNotify body order :43-44 (seeds attach one hook at a time) |
| 011.dup-silent | Add | rejected duplicate fires NOTHING | boundary | InternalDoAdd raises BEFORE AddItem's notify :399/:420 |
| 011.new-value-visible | SetItem | during old-removed the dict already holds the new value | boundary | SetValue assigns FIRST :58, then notifies — order read from source |
| 011.post-removal | Remove/Clear | callbacks observe the pair already absent / count 0 | boundary | DoRemove :477 and Clear :515 notify after mutation |
| 011.extracted-action | ExtractPair | dedicated 'extracted' action token | cross-check | cnExtracted :512; P6 relies on the distinction |
| 011.unhook/cb-rc/dangling | hooks | empty name stops events; cb rc ignored; dangling name skipped | bash-convention | bash-side hook lifecycle; FPC events cannot dangle |
| 011.sender | hooks | cb receives the instance name as $1 | bash-convention | Sender: TObject analog |
| 012.assign-events | Assign | old content removed + copies added | bash-convention | Assign is our Create(ACollection) analog; composition of pinned paths |
| 012.addpairs-events | AddPairs | per-pair added events | bash-convention | same composition |

## P6 — TObjectDictionary (013)

Seed-traceable core (no rows): freed-on-removed / kept-on-extracted / ownership
flags — read directly from the KeyNotify/ValueNotify overrides (impl:2389-2405);
FPC's own suite covers TObjectDictionary lightly, so most rows below pin
consequences derived from the override source.

| ID | Functions | Case | Class | Basis |
|---|---|---|---|---|
| 013.ctor-tokens | Create | space/comma token forms; '' = none; unknown token → rc 1, none applied | bash-convention | TDictionaryOwnerships set literal has no bash shape; atomic-reject is our contract |
| 013.overwrite-frees | AddOrSetValue, SetItem | replacing a value under doOwnsValues frees the OLD instance only | cross-check | SetValue fires old-removed (:54) + override frees on removed (:2403) — composition read from source |
| 013.dup-add-no-free | Add | failed duplicate frees nothing | boundary | raise precedes any notify (:399); composition with :2403 |
| 013.plain-string-skip | _free | non-instance item under ownership: silent no-op | bash-convention | bash items are strings, not object refs; liveness = `.delete` dispatcher exists |
| 013.callback-order | ValueNotify override | user event sees the instance ALIVE; freed right after | cross-check | `inherited` precedes Free in the override (:2392/:2401) |
| 013.leak-scan | Destroy/_free | freed instances leave no `<inst>_items` globals | representation | kklass storage lifecycle; guards the bash-side teardown |

## Finalization (P7)

Suite: **130 checks** across tests 001–013, green on bash 5.2.37 (primary) and
5.3.9 (secondary). FPC-traceable cases carry no rows here (seeds:
`tests.generics.dictionary2.pas` add/modify/remove matrix,
`tests.generics.dictionary.pas` TestKeys + four notification tests, plus
semantics read directly from `generics.dictionaries.inc` with line refs).

Non-FPC row breakdown — **58 rows total**:

| Class | Rows | Nature |
|---|---|---|
| boundary | 14 | edges FPC never exercises: empty key/value, miss paths of GetItem/SetItem/TryGetValue/Remove/ExtractPair, notify-timing observability |
| bash-convention | 23 | rc-vs-exception mapping, RESULT/RESULT_KEY, `$()` caveats, hook lifecycle, output-array contracts, ownership-token parsing, instance lifecycle |
| representation | 8 | exotic-key/value byte-exactness, storage-idiom torture, zero-fork guarantees, leak scans |
| cross-check | 13 | internal consistency: no-mutation on rejected ops, index alignment, event ordering, state-machine sequences, source-derived compositions |

Test-side traps pinned during the effort (also in PLAN.md §6):
- `$()` around a MUTATING call mutates only the subshell copy — capture stderr
  with a file redirect, never with command substitution (hit in 003/005/013).
- kklass restores the caller's RESULT when a `func` early-returns — miss paths
  must call `kk._return` explicitly (library-side fix, pinned by 004).
- Never edit the unit while a master sweep is in flight (P3-sweep race).
