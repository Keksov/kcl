# TTail — GNU `tail` wrapper over TUtil (kcl/ttail)

**Status: COMPLETE (P0–P1).** P0 DONE 2026-09-15 (unit + tests + README first
cut); **P1 DONE 2026-09-16** (bench.sh, tests/007_Bench.sh, README final,
TEST_COVERAGE_NOTES.md, kcl README §2 row, ledger COMPLETE) — the numbers are
under §4. Written together with
[`kcl/thead/PLAN.md`](../thead/PLAN.md); **everything in that plan applies here**
(source of truth, base, template, conventions, §2.1 tgrep rules, §2.2 count regex +
19-digit guard + the sign table, §2.3 `zeroTerminated` rule incl. the rc 2 for ≥ 2
paths / `verbose`, §2.4 headers-as-records, §2.5 mapRc + the two deviations, §2.6
CRLF, §2.8 the `__tt_` prefix in `tutil._badOut`, §4 test model, §6 traps, §8 critic
record). This file records only what differs.
**Ledger:** `kcl/ttail/ttail_ledger.json`. **Prefix:** `__tt_`. `ttail.sh` sources
`../tutil/tutil.sh` **only** — never `thead.sh` (`TTail : THead` would be wrong: `+N`
means different things), and the common `buildArgv` shape is duplicated on purpose.

---

## 1. What differs from head

### 1.1 Measured (coreutils 8.32, both bashes)

| probe | result |
|---|---|
| `-n +N` | **start at line N** (`tail -n +2` = skip the first line; `+0` = everything); `-n N` and `-n -N` = last N; `-n 0` / `-n -0` = nothing; `-c +N` / `-c N` likewise for bytes |
| `-f` | follows the file until killed; tail does not write while waiting, so SIGPIPE never fires — only the `kill -TERM` of the tpipe stop path ends it (rc 143, ~45 ms on both bashes; no `---disable-inotify` needed). There is no inotify on msys: a line appended 1 s later reached `each` after ~2 s (poll interval ~1 s); `first` on a follow stream took 0.05 s on 5.2.37 and 0.33 s on 5.3.9 |
| rc | `0` ok; `1` for every error incl. partial (`tail -n 1 a missing` prints a's line, rc 1) |
| everything else | as head: headers with several files unless `-q` (the `\n` prefix rule), `-z` (input re-delimited, headers `\n`-terminated), CR kept, `--`, stdin, `-n 08` decimal, last flag wins |

### 1.2 Surface

```bash
class TTail : TUtil
    public
        var lines           # -n N   (N = [+-]?digits ≤ 19; '+N' = from line N)
        var bytes           # -c N   (same forms); lines+bytes both set → rc 2
        var quiet           # -q
        var verbose         # -v     (quiet+verbose → rc 2)
        var zeroTerminated  # -z     → derives the sinks' -0 for one path (thead §2.3)
        var follow          # -f     (§2.1)
        var _nulDerived
        constructor Create  # [N [PATH...]]; parent.constructor tail; every var assigned
        destructor  Destroy
        proc paths
        override func buildArgv   # tail [-q|-v] [-z] [-f] [-n N | -c N] [extras] [-- PATH...]
        override func mapRc       # 0→0; else 1 + debug
        override func toArray     # follow = 1 → rc 2, nothing runs (§2.1); else inherited
        override func toList      # same
        override func count       # same
        static proc take          # TTail.take N PATH... → `tail -n N -- PATH...`; ≥1 path required
end
```

argv shape, pinned: `tail` `[-q|-v]` `[-z]` `[-f]` `[-n N | -c N]` `[EXTRA]` `[-- PATH...]`.
`t.argv V` with `follow = 1` still yields `-f`: the refusal below is a **sink** rule,
not an argv rule.

## 2. Decisions specific to tail

### 2.1 `follow` and the sinks

`tail -f` never ends on its own. `buildArgv` cannot refuse per sink (it does not know
its caller — the critic measured `tutil._prep`'s `__tu_m` unset on the `argv`/`run`
paths), so the split is implemented by **overriding three sinks** in TTail:

| member | with `follow = 1` |
|---|---|
| `run` | streams until the caller kills it (Ctrl-C, `timeout`, a `kill` from elsewhere) |
| `each` | streams until the callback calls `TPipe.stop`; then the tpipe stop path (close → `kill -TERM` → wait) ends tail with rc 143 → member rc 0, `lastRc` 143. **Blocks forever with a callback that never stops**; there is no timeout and no cancellation from outside — a caller who cannot guarantee a stop uses `run` under an external `timeout` |
| `first` | one record, then the stop path — the "wait for the next line" idiom; blocks until a record arrives |
| `toArray`, `count`, `toList` | **rc 2 in the overriding member, nothing runs**: the first two can only finish at EOF, which never comes; `toList` could only finish if `.Add` called `TPipe.stop`, and **no kcl list does** (`TStringList`/`TList`/`THashSet.Add` never stop) |

The three overrides use the spelling of thead §6: a body that merely ends on
`inherited toArray "$@"` returns 0 where the base returned 1 (the compiled
`kk._return` trailer replaces the rc — measured), so:

```bash
TTail.toArray() {
    if [[ "$follow" == 1 ]]; then
        kk.debug "Error: TTail.toArray: cannot finish with follow = 1 (tail -f never reaches EOF); use each with a stopping callback, first, or run"
        kk._return ""
        return 2
    fi
    local __tt_rc=0
    inherited toArray "$@" || __tt_rc=$?
    local __tt_n="$RESULT"
    kk._return "$__tt_n"
    return "$__tt_rc"
}
```

Pinned: with `follow = 0` and one missing operand every overridden sink still answers
rc 1 with RESULT = the real count (the naive spelling would answer 0); with
`follow = 1`, `toArray`/`count`/`toList` are rc 2 and a flag-file producer proves
nothing ran; `each` + a stopping callback → rc 0 / lastRc 143 / one record in a child
under `timeout 20`; `first` returns the last line then stops. `--pid=PID` via `addArg`
is the only shape in which `-f` terminates on its own (once PID dies); the refusal is
not lifted by inspecting `${inst}_args` — a caller who needs that uses `run`.

This supersedes tutil PLAN §7's "sinks refuse, run only" (amended by thead §2.9).

### 2.2 `+N`

The regex of thead §2.2 already admits `+N`; here it has a meaning worth its own
pins: `t.lines = +2; t.count` on a 5-line file is 4; `TTail.take +2 f` == `tail -n +2
-- f`; `-n +0` is everything, `-n -0` nothing (the mirror of head). `kk.isInt` would
have silently turned `+2` into `2` (last two lines) — the reason thead §2.2 forbids it
applies twice here.

## 3. Pinned facts (tests) — in addition to thead H1–H12 mirrored for tail

| # | fact | test |
|---|---|---|
| T1 | `-n +2` / `-n 2` / `-n -2` / `-c +3` verbatim in argv; behaviour vs bare tail incl. `+0`/`-0`/`0` | 004/005 |
| T2 | `follow = 1`: `toArray`/`count`/`toList` rc 2 + nothing runs; `each` + stop → rc 0, lastRc 143, one record; `first` returns the last line then stops; `run` on a file that grows (a background appender started by the test, ≥ 3 s of slack for the ~1 s poll) delivers the appended line before the child's `timeout` ends it; **every follow test records its producer's pid and `kill -TERM`s it in the test's own teardown** (no `EXIT` trap; leaked followers from earlier sessions were found on this box) | 005 |
| T3 | overridden sinks with `follow = 0` and a missing operand: rc 1, RESULT = real count (not 0) | 005 |
| T4 | `TTail.take +2 f` == `tail -n +2 -- f` | 005 |

## 4. Phases

Same two phases as thead, in the same worker cycles: **P0** unit + 004/005/006 +
README first cut (+ the shared tutil edits listed in thead §5 P0); **P1** bench (`take`
vs bare `tail -n`, interleaved medians ≥ 15 runs, gate 1.5×) + 007 (10× ceiling) +
docs + kcl README §2 row + ledger COMPLETE.

**P1 DONE 2026-09-16.** Delivered: `bench.sh` (sections a–e, the thead shape;
the argv proof runs with `follow = 1` set, so it also pins that `-f` reaches the
argv while three sinks refuse it; the GATED `TTail.take` vs the bare tool in the
`-n 1` and `-n 5000` shapes, interleaved, medians of NR = 21, means beside them;
`count` vs the `wc -l` equivalent published, not gated; zero forks over every
member, `take`, **and the three `follow = 1` refusals**; no follower is ever
started — rc 0 under `bash -eu` on both bashes), `tests/007_Bench.sh` (10 cases,
10× ceiling, 2000-line corpus, no follower), README final (§9 Performance,
§10 Tests), `TEST_COVERAGE_NOTES.md` (200 rows), the kcl README §2 row, the
ledger. Measured on an idle box against GNU coreutils 8.32:

| | bash 5.2.37 | bash 5.3.9 |
|---|---|---|
| `take 1` vs bare `tail -n 1` (medians of 21) | 39.13 / 35.03 ms = **1.11×** | 38.72 / 35.08 ms = **1.10×** |
| `take 5000` vs bare `tail -n 5000` | 37.57 / 33.72 ms = **1.11×** | 38.10 / 32.56 ms = **1.17×** |
| `new` + `argv` + `delete` (the delta) | 3202.1 µs/call | 3333.2 µs/call |
| `buildArgv` / `argv NAME` | 679.2 / 1282.2 µs | 661.9 / 1385.8 µs |
| `t.count` vs `tail -n 5000 \| wc -l` (published) | 734.09 / 55.60 ms = 13.20× | 738.49 / 47.26 ms = 15.62× |
| gates | **2/2 PASS** | **2/2 PASS** |

`follow` is deliberately **not** benched: `tail -f` never ends on its own, so
nothing about it is a per-call cost (§2.1). Suite after P1: **200/200** on bash
5.2.37 and on 5.3.9, threaded and under `--mode single`, with no follower of
ours surviving a run.
