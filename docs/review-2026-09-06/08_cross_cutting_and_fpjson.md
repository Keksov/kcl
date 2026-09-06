# Reviewer report G8 — cross-cutting pass + fpjson design review (2026-09-06)

Repro scripts: `repro/g8/hygiene.sh`, `hygiene2.sh`, `errprobe.sh`, `contract.sh`, `inj.sh`, `uprobe.sh`, `sweep.sh`, `jsonprobe*.sh`.

### Summary
Master sweep on bash 5.2.37 = 20 suites / 3066 tests / 0 FAIL (kcl 17 suites = 2261), repo tree unchanged by the sweep; bash 5.3.9 sweep = identical totals, 0 FAIL, no 5.2-vs-5.3 delta. Top 3 cross-cutting issues: (1) HIGH arithmetic injection through user-supplied indices/numbers in the tlist family, tarray.sort, tstringhelper and dateutils; (2) MED every unit (and kklass_pascal.sh) is unsourceable under `set -u`; (3) MED five different boolean/return conventions across units plus a stdout-vs-RESULT split. fpjson PLAN's core perf assumption is wrong (pure `${s:i:1}` loop is O(n²): 96 KB = 45 s on 5.2) but a windowed lexer fixes it (1.7 s).

### Task 1 — loading / dependency hygiene
Facts (`hygiene2.sh`, all 17 units in one shell, 5.2 and 5.3): sourcing all units prints nothing, rc 0; tlist→tstringlist→tobjectlist→tqueuestack (tlist sourced 3× via different `..` paths) triggers no kklass duplicate-class warning; `set -o`/`shopt -p`/IFS/pwd/traps identical before vs after; no jobs/coprocs left (math engine is lazy). tdirectory toggles `extglob` inside 5 methods and restores it. No `__x_` global prefix collides across units (`__kdt_ __ta_ __td_ __ts_ __tif_ __tol_ __tqs_ __trx_/__tre_ __tsw_ __tsl_`).

`G8-01 | MED | all units + kklass | e.g. dateutils.sh:48, tpath.sh:5, tqueuestack.sh:61, kklass/kklass_pascal.sh:42 | re-source guard breaks every unit under set -u`
`bash -c 'set -u; source kcl/tpath/tpath.sh; tpath.combine a b'` → `tpath.sh: line 5: _TPATH_SOURCED: unbound variable`. All 17 fail (the ones without an own guard die inside kklass_pascal.sh:42). Fix: `${_X_SOURCED:-}` everywhere.

`G8-02 | MED | math | math.sh:474-485,504 | awk program temp file leaks on shell exit` (= M6).

`G8-03 | LOW | tlist tdictionary tstopwatch | :6-7 | kerr.sh/klib.sh sourced but never used` — zero `ke.*` calls in any unit. (R14.)

`G8-04 | LOW | kklass | kklass.sh:138,634-873 | loop variables p / sm / wm leak as globals; METHOD_BODY, METHOD_WRAPPER, … become globals`; `tstringhelper_DIR` is the only lowercase `_DIR`.

### Task 2 — error-handling consistency (measured)

| unit | value return | error report | boolean answer |
|---|---|---|---|
| tlist / tstringlist / tobjectlist | RESULT (silent) | rc 1, silent unless `VERBOSE_KKLASS=debug`; RESULT untouched on OOR | rc |
| tdictionary | RESULT | rc 1 silent-unless-debug; `GetItem` miss RESULT=""; `Remove` miss rc 0 | rc |
| thashset | RESULT | `Remove` miss rc 1 silent; `Extract` miss rc 0 RESULT=""; Assign bad operand loud stderr | rc |
| tqueuestack | RESULT | rc 1 + RESULT="" silent-unless-debug; ctor bad token loud stderr | rc |
| tinifile | RESULT | typed misses → default rc 0; UpdateFile to nonexistent dir creates it | RESULT=1 |
| tstopwatch | RESULT | rc 1 silent-unless-debug | RESULT=1 |
| tcustomapplication | RESULT | rc 0 + RESULT=""; `CheckOptions` message in RESULT | RESULT="false" |
| tarray | RESULT (silent static proc) | rc 1/2 silent; `sort` on undefined array rc 0 | RESULT=-1 |
| tregex | RESULT* globals; `escape` prints AND sets RESULT | rc 1/2 silent | rc |
| dateutils | stdout | rc 1 silent; `decodeDate abc` prints `1970 1 1` rc 0 | prints `true/false` |
| math | stdout (RESULT never set, REPLY = junk) | never fails | prints |
| tdirectory | stdout | always loud `Error: … >&2` + rc 1 | prints `true/false` |
| tfile | stdout | rc 1 silent | prints `true/false` |
| tpath | stdout | rc 0 for empty inputs | prints |
| tstringhelper | stdout | rc 0 always; `chars abc 10` prints `undefined` | prints `true/false` |

`G8-05 | MED | cross-unit | Three error conventions and five boolean conventions coexist` (decision D2/D3/R8).

`G8-06 | HIGH | tlist (+tstringlist, tobjectlist), tarray, tstringhelper, dateutils | user-supplied indices/numbers go straight into (( )) — code execution` (`inj.sh`; = X-INJ; D1).

`G8-07 | LOW | kklass under set -e | boolean-false proc under set -e aborts with a spurious "pop_var_context" message` — documents that rc-based booleans must be used via `if`/`||` under `set -e` (D7).

### Task 3 — test infrastructure
Master runner discovers any `<dir>/tests/tests.sh` recursively: 20 suites (17 kcl + kklass + kkore + ktests). fpjson/tests empty → silently skipped. ktests runs test files with 8 parallel workers. `git status --porcelain` in kbool, kcl, kklass identical before/after both sweeps; `.ckk` set unchanged; no new `/tmp/.math_fe_*` from the tests. The known "5.3-only 033 compiled-path failure" did not reproduce.

`G8-08 | LOW | tests | tcustomapplication 004,016 (8× sleep 0.1), tdirectory 016 (sleep 1); tinifile 001_Skeleton.sh:23-55 and tcustomapplication 019 use fixed /tmp names under an 8-worker runner`.

### Task 4 — documentation / ledger drift
Ledger test counts match the sweep; phases claimed done have their methods present; thashset P2/P3 members are explicit stubs; fpjson: 0 code, 0 tests.

`G8-09 | LOW | math, tarray, tdictionary, tinifile, tobjectlist, tqueuestack, tregex, tstopwatch *_ledger.json "status" | say UNCOMMITTED / COMMITS GATED although committed` (5531542, 229e51a, 3a529b0, fcde032, 9cd37b4, d5c2a6c, c0d093c, 1544cb4). Only thashset is genuinely untracked.

`G8-10 | LOW | tcustomapplication tdirectory tfile tlist tpath tstringhelper tstringlist | docs/*.md | no bash API docs at all — only scraped upstream references, zero README` — they describe members the port does not have and omit what exists.

### Task 5 — fpjson design review (measurements from `jsonprobe2.sh`/`jsonprobe3.sh`, taken under load; ratios hold)
- Node model: object-per-node correctly rejected (`TDictionary.new` ≈ 1.2 ms under load, method call ≈ 0.47 ms; 10k nodes ≈ 150k shell functions). Document instance + integer handles in parallel arrays is right: 10k nodes into 3 indexed arrays = 90 ms. Corrections: children as a space-separated id list in `${doc}_kids[id]` (not a `\x1f` scalar); reserve `_type/_value/_kids/_names/_parent/_next` suffixes and free them in the destructor; add `_parent[id]` (Delete/Remove/Clone/FindPath `..` need it).
- Parser: `${s:i:1}` on a large string is O(n) per access: byte loop 19 KB = 1.6 s, 96 KB = 45 s on 5.2 (19 s on 5.3); windowed loop (`w=${s:p:2048}`) does 96 KB in 1.7 s; a regex tokenizer (`[[ $window =~ ^(token) ]]`, 300-byte window) ~2× faster again and yields whole tokens. awk one-shot tokenize of 96 KB = 1.7–4.5 s incl. fork — not a free win; persistent awk coproc only pays for >20 KB.
- Unicode: `printf '\U0001F600'` and lone surrogates print LITERALLY in this environment (C locale) — encode UTF-8 by hand from the code point; lexer must pin `LC_ALL=C`; test byte-vs-char under a UTF-8 locale.
- Missing from the plan: `_parent`, FindPath grammar for names with `.`/`[`, duplicate-key policy on parse and serialize, max-depth default, error contract alignment (D2), `AsJSON` of control chars, teardown cost test (10k nodes), `-0`/`1E400`/int64 number tests.
- Recommendation (decision D8): pure bash handle model + regex-window tokenizer, explicit stack, `LC_ALL=C` scoped, target ≤1 s / 20 KB; awk coproc deferred to P8.

### Task 6 — `.ckk`
`kcl/.gitignore` uncommitted change adds `**/.ckk`. Existing dirs: `kcl/.ckk`, `kcl/tinifile/.ckk`, `kcl/tlist/.ckk`, `kcl/tqueuestack/.ckk` (plus kbool/, kklass/, kklass/examples/, kklass/tests/). Creator: `kklass/kklass_autoload.sh:60` writes to `${KKLASS_CKK_DIR:-$(pwd)/.ckk}`; kklass tests 063/065 hard-code `$(pwd)/.ckk/sample_counter…` and test 030 compiles into `$PWD` — confirmed live: `kbool/.ckk/*` rewritten by the sweep's kklass suite (cwd = kbool). The kcl dirs date from July when sweeps ran with cwd = a unit dir. `**/.ckk` is a valid symptom fix; root cause is kklass tests 030/063/065 (R15).

### Test gaps
- No suite runs under `set -u` or `set -e`.
- No cross-unit test loads all 17 units in one shell.
- No negative test for non-numeric / injection-shaped indices in tlist family, tarray.sort, tstringhelper, dateutils.
- No test that math leaves no `/tmp/.math_fe_*` behind on plain shell exit.
- Sweep never runs under a UTF-8 locale.
- Return-contract tests exist per unit but assert different contracts; nothing pins one kcl-wide convention.
