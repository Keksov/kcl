# kcl deep review — shared brief for reviewers

Repo: c:\projects\kkbot\kbool (git). kcl = submodule at kbool/kcl: bash ports of Free Pascal RTL/FCL classes,
built on the kklass bash OOP framework (kbool/kklass) and kkore helpers (kbool/kkore).
You are READ-ONLY on the repo: never edit, create, delete or git-touch anything under c:\projects\kkbot.
Use the scratchpad dir given in your prompt for any temp files.

## Environment
- Primary bash: 5.2.37 (MSYS2) = plain `bash` in the Bash tool.
- Secondary bash 5.3.9 (cygwin): run as
  PATH="/c/bin/msys64/usr/bin:$PATH" /c/bin/msys64/usr/bin/bash.exe <script>
- Unit tests: `bash kcl/<unit>/tests/tests.sh --verbosity info` (ktests framework; kt_test_start/pass/fail).
  Tests print nothing on pass at default verbosity. Do NOT run two suites concurrently.
- Load a unit in a scratch script: `source /c/projects/kkbot/kbool/kcl/<unit>/<unit>.sh` (it sources kklass itself).
- `python` is a broken Store stub here — never call it. perl/awk/sed are fine.

## kklass contracts you must judge code against (as of 2026-09-05)
- Methods: `func` returns via `kk._return VALUE` -> caller reads `$RESULT`. A DIRECT call (`obj.m args`) prints
  NOTHING and sets RESULT; inside `$( )` the value is echoed exactly once. Idiom in kcl: `obj.m >/dev/null; use $RESULT`
  or just `obj.m; use $RESULT`. `$(obj.m)` forks a subshell (expensive, and mutations inside are LOST).
- Computed properties: same contract (direct read silent + RESULT; `$()` prints once).
- Static methods with static properties: state changes are lost under `$(Class.m)`; value also in `REPLY`.
- Instance = `<inst>_data` assoc array + `<inst>_class` + `<inst>.<member>()` wrappers. `obj.delete` runs the
  destructor, unsets data/class vars and wrappers listed in class tables. Extra per-instance arrays a unit creates
  itself (e.g. `${inst}_items`) are NOT freed by kklass — the unit's destructor must do it.
- Reserved member names: this __inst__ __class__ RESULT REPLY IFS and anything starting with __kk_.
- `inherited`/`.parent` resolve from the DEFINING class; `.call` is virtual.
- Forks (`$(...)`, pipes, external commands) in hot paths are the #1 perf sin: fork copies the whole shell,
  ~1-16 ms each once many instances exist.

## What to look for (in priority order)
1. Correctness bugs: wrong results, crashes, silent data loss, off-by-one, wrong FPC semantics where the unit
   claims FPC parity (check docs/README claims against behaviour), unhandled empty/edge inputs (empty string,
   spaces, glob chars `*?[`, leading `-`, newlines, very large counts, negative indices).
2. Bash pitfalls: unquoted expansions, word splitting, glob expansion, `IFS` leaks, `set -e`/pipefail interaction,
   `local` shadowing, nameref collisions (`local -n x` where a caller variable is also named x), `eval` on user data
   (injection), `[ ]` vs `[[ ]]`, `echo` of data starting with `-n`/`-e`, `read` without `-r`, arithmetic on
   non-numeric input (`$(( ))` with user strings = code execution).
3. Resource/lifecycle: instance leaks (per-instance arrays not freed in destructor), temp files not removed,
   background processes, global namespace pollution, re-source guards.
4. Performance: forks in hot paths, O(n^2) where O(n) is easy, `$(...)` where RESULT idiom exists.
5. Error handling consistency: kerr usage, exit statuses, messages to stderr vs stdout, loud vs silent contract.
6. Tests: what is NOT covered, tests that cannot fail (assert on wrong thing), tests depending on cwd/state/timing.
7. Docs/ledger drift: README/docs/TEST_COVERAGE_NOTES claims that no longer match code.

## Method
- Read every source file of your units completely. Read the tests. Skim docs/README for claims.
- For EACH suspected bug, write a small scratch script and RUN it on bash 5.2 (and 5.3 if version-relevant).
  Only report findings you reproduced, or clearly mark unreproduced ones as "SUSPECTED" with the reason.
- Run the unit test suites once on 5.2 and report the counts.
- Do not propose rewrites of the architecture; the owner wants concrete defects and concrete gaps.

## Report format (return this as your final message; be complete but terse; no fluff)
### Summary
one paragraph: unit health, test counts, top 3 issues.
### Findings
For each: `ID | severity(HIGH/MED/LOW) | unit | file:line | title`
then 2-6 lines: what happens, repro command + observed vs expected, FPC-parity note if relevant, suggested fix (1 line).
Severity: HIGH = wrong result/data loss/crash/injection in normal use; MED = edge-case bug, perf fork in hot path,
leak; LOW = docs drift, style, test gap.
### Test gaps
bullets.
### Questions for the owner
Design decisions you could not settle (2-6 max), each with 2-3 options and your recommendation.
