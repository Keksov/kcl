# Worker brief — kcl fix plan, one phase per assignment

You implement ONE phase of `c:\projects\kkbot\kbool\kcl\PLAN.md` at a time, then report to the reviewer
(the session that spawned you). The reviewer verifies your report against the live tree, sends remarks,
and commits when the phase is clean. You NEVER commit and NEVER push. You NEVER start the next phase on
your own — you wait for the reviewer's message.

## Read first, in this order (no skipping)
1. `kcl/PLAN.md` fully: §0 environment/run/contracts/tree state, §1 decisions D1–D8 (binding), §2 defaults
   R1–R15 (binding unless the reviewer says otherwise), §3 your phase, §4 red-first rule, §5 gates.
2. `kcl/kcl_ledger.json` — see how P0 and P1 recorded `closed` entries (fix / test / red_before); do the same.
3. `kcl/README.md` — the normative contract every unit must meet after your phase.
4. `kcl/REVIEW.md` — the section(s) for your units.
5. The full reviewer report(s) for your units in `kcl/docs/review-2026-09-06/0N_*.md` and the repro scripts in
   `kcl/docs/review-2026-09-06/repro/gN/` (their `K=`/source paths may point at an old scratchpad — fix them).
6. `kcl/docs/review-2026-09-06/00_BRIEF.md` — kklass contracts used to judge the code.

## Environment (critical)
- Windows 11 / MSYS2. bash 5.2.37 = `bash`. bash 5.3.9 = `C:/bin/msys64/usr/bin/bash.exe`, run suites ONLY as
  `PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe tests/tests.sh` (else 0 tests reported).
- `python` in PATH is a Store stub that hangs — use perl/awk/sed.
- Suites and the two bashes run strictly SEQUENTIALLY (race on `tests/.ckk` and `/tmp`).
- Read sweep results by grepping ALL `[FAIL]` lines, never the tail.
- Never enumerate a big shell's function table (`compgen -A function`).
- Forks in hot paths are forbidden; prove direct calls are fork-free with `$BASHPID`.
- Temp files go to your scratchpad dir (given in the assignment), never `/tmp`, never the repo.
- Locale: ktests pins `LC_ALL=C.UTF-8`; a test of the unit's own locale self-heal must run a child bash with
  `LC_ALL`, `LC_CTYPE`, `LANG` cleared.

## Rules of work
- **Red first.** For every finding ID you close: write the regression test (ID in its name/description) BEFORE
  the fix, run it on the current code, it MUST fail; record the actual FAIL count. If it does not fail, rewrite
  the test, do not skip the fix. Then fix, then green. Rewrite weak asserts you meet (`$? -eq 0`, either-of-two,
  substring, guarded branches, unconditional pass).
- **No mechanical sweeps applied blind.** Two earlier sweeps corrupted sources (a literal newline inside a
  `printf '%s` format; a regex that swallowed following statements) while tests stayed green. Every contract
  test now runs `bash -n` + a dangling-quote check; keep them green and read every diff hunk you generate.
- Bash facts already settled (do not "fix" them): mid-body `[[ c ]] && cmd` lists are safe under `set -e` on
  5.2 and 5.3; only a `&&` list as the LAST statement of a function and bare `(( ))` evaluating to 0 break it.
- Stay inside the phase. If you find a defect outside it, add it to the ledger as `found_in_<phase>` with a repro
  and leave it, unless it blocks the gate.
- FPC parity is the reference (FPC 3.2.2 sources: `classes`/`contnrs`/`generics.collections`, etc.). When the
  review report and FPC disagree, FPC wins and you say so in the report.
- Update as you go: `kcl/PLAN.md` (a **DONE <date>** block under the phase like P0/P1 have), `kcl_ledger.json`
  (phase `status: done`, `closed` map with fix / test / red_before per finding, gate numbers, deviations), the
  unit's own README/ledger/TEST_COVERAGE_NOTES where they exist, docs drift named in the findings.
- Do not touch `thashset/` beyond what your phase names. Do not touch kklass/kkore/ktests unless your phase
  names them; if a framework change is unavoidable, stop and report first.

## Gate (before you report)
1. Suites of the phase's units: 0 FAIL on 5.2.37 and on 5.3.9 (sequentially).
2. `bash kbool/tests/tests.sh`: 0 FAIL on both bashes; all `[FAIL]` lines grepped.
3. `bench.sh` of touched units where present: no metric slower than before; for perf findings, the relative
   gate named in the plan.
4. `git status` in kbool, kcl, kklass, kkore, ktests: only your phase's changes (+ the known thashset WIP).
5. No new `.ckk`, `.tmp`, `/tmp/.math_fe_*` left behind.

## Report format (your final message; terse, factual, numbers not adjectives)
1. Gate table: per suite 5.2 / 5.3 counts; master sweep both bashes; `[FAIL]` grep count.
2. Red-first table: test file -> FAIL count before the fix -> now.
3. What was done, per finding ID (one line each), incl. FPC checks made.
4. Deviations from the letter of the plan, each with the reason (the reviewer must approve them).
5. Findings outside the phase you noticed (ledger `found_in_*`), not fixed.
6. Open questions for the reviewer (only if a decision is genuinely needed; otherwise pick the default and say so).
7. Files changed (git status --short of each repo).

## Waiting for long commands (added 2026-09-07 after a worker polled with `echo` for an hour)
- Run suites and sweeps in the FOREGROUND with an explicit `timeout` of up to 600000 ms (a master sweep on one
  bash takes ~8–9 min; that fits). Do not launch them in the background and then "wait".
- NEVER poll with no-op commands (`echo`, `sleep`, `true`, repeated `cat` of an output file). If a background
  command is running, the harness notifies you when it finishes; do nothing until then, or do other useful
  work that does not touch the same files.
- If something genuinely needs more than 10 minutes, split it (e.g. run the two bash versions as two separate
  foreground commands).
