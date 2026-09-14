# tutil — test coverage notes

**Status: FINALIZED at P3 (2026-09-11).** Suite `001`–`004` = **172 cases**,
green on bash 5.2.37 (primary) and on bash 5.3.9 (secondary), in the default
threaded mode and under `--mode single`. The per-file row counts below sum to
172 — 61 + 56 + 47 + 8 — and **every case in the suite has a row**.

**Protocol.** `TUtil` has **no upstream to port**: it is a kcl addition in the
spirit of FPC `fcl-process` `TProcess` (decision D3), so there is no Pascal seed
procedure to cite and nothing to argue from a FPC source. Two things stand in
for it:

* **the bare tool** — every sink's answer is compared with `TPipe` called
  *directly* on the argv the wrapper built, and `run`'s stream is compared
  byte-for-byte with the tool run by hand;
* **a list of measured facts** about bash and kklass, each of which is a rule the
  unit is written around (`PLAN.md` §6) and each of which is a test.

The Basis column therefore cites one of:

* **U1–U8** — a pinned fact of `PLAN.md` §3.
* **C1–C23** — a finding of the 2026-09-10 critic pass (`PLAN.md` §8, same
  numbering). The measurement behind each blocker, as a runnable script with its
  output on both bashes, is [docs/TUtil.md §3](docs/TUtil.md#3-the-measurements).
* **P0-Fn / P1-Fn / P3-Fn** — a finding made by the implementing worker in that
  phase (`tutil_ledger.json` `execution_log`).
* **D2 / D6** — a `TPipe` decision this unit inherits (tpipe `PLAN.md` §2.0).
* **§n** — a plain section of `PLAN.md` or of `README.md` where the rule is
  stated and nothing else needed proving.

**Classes.**

| Class | Meaning |
|---|---|
| `contract` | the kcl contract (`../README.md` §1): rc mapping, `RESULT`, silence, validation order, `set -eu` cleanliness, lifecycle, zero forks |
| `bash-convention` | a bash or kklass fact the design rests on — the `declare -f`/`eval` round trip, dynamic scoping, namerefs, `set -u` on an unset key, subshells |
| `representation` | records and argv words are **data**: exotic bytes, a CR, a NUL delimiter, a leading `-`, a space, UTF-8, byte-exact round trip |
| `boundary` | an edge the happy path never reaches: an empty producer, an unterminated tail, nesting, a second instance on the same name, a rejecting `.Add` |
| `cross-check` | the member's answer against an oracle — `TPipe` called directly, or the bare tool |
| `perf` | a `PLAN.md` §5 P3.1 gate, asserted with a loose ceiling |

**Deliberate gaps** (each is a `wontfix` of `PLAN.md` §1.4 or of
[docs/TUtil.md §1.2](docs/TUtil.md#12-wontfix-and-why), and none is testable as a
behaviour of this unit):

* **the tool's stderr** — it passes through by design, so every silence assertion
  is scoped to *our own* output and the tool's `2>` stream is explicitly allowed
  through (003 separates the two);
* **writing to the tool's stdin** — deferred (`stdinFrom`); today it is the
  caller's redirect, and the only thing pinned is that a **refused** call leaves
  stdin unread (001 §D);
* **`CurrentDirectory` / `Environment` / the handle-and-lifecycle family** — not
  modelled at all, so there is no behaviour to assert;
* **BSD/macOS flag dialects** (D4) — a wrapper's tests assert the GNU banner
  first and are silent about anything else;
* **a record containing a NUL byte** — no bash variable can hold one (`TPipe`'s
  own limit, tpipe `README.md` §7).

---

## 001_Core.sh — the core: argv model, `run`, `mapRc`, lifecycle (P0) — 61 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 001.parse | — | the unit source parses (`bash -n`) | contract | §4 — two earlier sweeps corrupted sources while tests stayed green |
| 001.openquote | — | no single-quoted `printf` format is left open at end of line | contract | §4 |
| 001.data-defaults | Create | right after `new`, `${inst}_data` lists `cmd`/`crlf`/`nul`/`_lastRc` with the documented defaults | contract | **U3**, **C3** |
| 001.arrays-created | Create | `${inst}_args` and `${inst}_argv` exist as EMPTY indexed arrays right after `new` | contract | **U3**, §2.1 |
| 001.lastrc-initial | lastRc | `lastRc` is `-1` until something ran | contract | §2.1 — `RESULT=-1` has corpus precedent (tarray, tlist) |
| 001.delete-frees | Destroy | after `delete` neither `${inst}_args` nor `${inst}_argv` nor `${inst}_data` exists | contract | **U3**, §1.9 |
| 001.reuse-clean | Create | a SECOND instance reusing the name starts empty — no storage left over | boundary | **C3** — `.new` over a live instance does not clear `_data` |
| 001.setu-vars | Create | every declared var is readable under `set -u` right after `new` | bash-convention | **C3** — unbound on 5.3.9, silently empty on 5.2.37 ([docs §3.3](docs/TUtil.md#33-c3--an-unassigned-var-is-unbound-under-set--u--and-the-two-bashes-disagree)) |
| 001.ctor-verbatim | Create | constructor arguments reach `Create` verbatim, `--format=%H` included | representation | **U2**, §1.2 |
| 001.buildargv-base | buildArgv | fills `${inst}_argv` with `cmd` + args; RESULT = the count | contract | **U2** |
| 001.buildargv-rebuild | buildArgv | calling it twice does not accumulate | boundary | §2.2 |
| 001.argv-copy | argv | `argv NAME` copies the built array into the caller; RESULT = the count | contract | **U2**, §1.7 |
| 001.argv-is-copy | argv | the caller's array is a COPY — mutating it does not touch `${inst}_argv` | contract | §1.7 |
| 001.argv-runs-nothing | argv | `argv` runs NOTHING: no process, no side effect | contract | §1.2 — the reason the argv pins are the fast half of a wrapper's suite |
| 001.addarg | addArg | APPENDS to `${inst}_args` and reaches `argv` | contract | **U2** |
| 001.addarg-empty | addArg | `addArg` with no arguments is a no-op | boundary | §1.2 |
| 001.cleargars | clearArgs | EMPTIES `${inst}_args`; `argv` is then `cmd` alone | contract | **U2** |
| 001.cmd-empty-build | buildArgv | `cmd=''` → rc 2, `RESULT=''`, `${inst}_argv` left empty | contract | **U4** |
| 001.cmd-later | cmd, buildArgv | `cmd` assigned later makes `buildArgv` succeed — the property IS the surface | contract | §1.2 |
| 001.out-state | argv | out-name `state` → rc 2 (kklass binds it onto `${inst}_data` in every frame) | contract | §1.7, **C22** |
| 001.out-result | argv | out-name `RESULT` → rc 2 | contract | §1.7 |
| 001.out-tu | argv | out-name `__tu_x` → rc 2 (this unit's own local prefix) | contract | §1.7 — bash scopes locals dynamically |
| 001.out-tg | argv | out-name `__tg_x` → rc 2 (the tgrep prefix, reserved from P0) | contract | §2.1 |
| 001.out-args | argv | out-name `${inst}_args` → rc 2 | contract | **C22**, §2.1 |
| 001.out-argv | argv | out-name `${inst}_argv` → rc 2 | contract | **C22** |
| 001.out-paths | argv | out-name `${inst}_paths` → rc 2 (reserved for TGrep from P0) | contract | §2.1 |
| 001.out-data | argv | out-name `${inst}_data` → rc 2 (the kklass storage) | contract | §1.7 |
| 001.out-dotted | argv | out-name `a.b` → rc 2 (not a plain identifier) | contract | §1.7 |
| 001.out-digit | argv | out-name `1bad` → rc 2 | contract | §1.7 |
| 001.out-empty | argv | out-name `''` → rc 2 (missing operand) | contract | §1.7 |
| 001.out-noside | argv | a refused out-name does NOT create the variable as a side effect | contract | §1.7 — the name is validated BEFORE any nameref is bound |
| 001.out-good | argv | a GOOD out-name still works after all eleven refusals | contract | §1.7 |
| 001.run-cmd-empty | run | `cmd=''` → rc 2, NOTHING runs, and a here-string on stdin is left unread | contract | **U4** |
| 001.argv-cmd-empty | argv | `cmd=''` → `argv` is rc 2 as well and nothing runs | contract | **U4** |
| 001.run-missing | run, lastRc | a missing command → rc 1, `lastRc` 127, and NOTHING runs | contract | **U5**, **C15** |
| 001.run-missing-quiet | run | with the debug switch OFF the missing command is COMPLETELY silent | contract | **C15** — bash's own line would be unconditional ([docs §3.5](docs/TUtil.md#35-c15--the-command-not-found-line-comes-from-bash-not-from-us)) |
| 001.run-missing-one | run | under `VERBOSE_KKLASS=debug` exactly ONE stderr line | contract | **U5**, §1.2 |
| 001.run-exit3 | run, lastRc | a tool exiting 3 → rc 1, `lastRc` 3, silent | contract | §2.4 |
| 001.run-exit3-debug | run | a tool exiting 3 stays silent under the switch too — only `127` speaks | contract | §2.4 |
| 001.run-exit0 | run, lastRc | a tool exiting 0 → rc 0, `lastRc` 0 | contract | §2.4 |
| 001.run-two-inst | run, lastRc | two instances interleaved keep SEPARATE `_lastRc` | contract | §2.3 — two wrappers may interleave |
| 001.run-cmdsubst | run | `$(u.run)` is byte-identical to the bare tool | cross-check | **U7**, **C1** |
| 001.run-procsub | run | `od -c < <(u.run)` is byte-identical to the bare tool | cross-check | **U7**, **C1** — this is the position that leaked `2…0` |
| 001.run-pipe | run | `u.run \| od -c` is byte-identical to the bare tool | cross-check | **U7**, **C1** |
| 001.run-exotic | run | a producer emitting `-n`, a backslash, a glob, a CR and an unterminated tail — all three positions byte-exact | representation | **U7** |
| 001.run-direct | run | the direct call prints the tool's stream and nothing else | contract | §1.1 deviation — `run` streams by definition |
| 001.run-rebuild | run, buildArgv | `run` REBUILDS the argv: a changed `cmd` is used on the next run | contract | §2.2 |
| 001.maprc-0 | mapRc | `mapRc 0` → RESULT 0, rc 0 | contract | §2.4 |
| 001.maprc-3 | mapRc | `mapRc 3` → RESULT 1, rc 0, silent under the switch | contract | §2.4 |
| 001.maprc-127 | mapRc | `mapRc 127` → RESULT 1, rc 0, EXACTLY ONE debug line | contract | §2.4 |
| 001.maprc-127-quiet | mapRc | `mapRc 127` is silent with the switch OFF | contract | §1.2 |
| 001.maprc-1 | mapRc | `mapRc 1` → RESULT 1 — the base has no "no match" case; TGrep overrides it | contract | §2.4 |
| 001.eu-load | — | the unit loads under `set -eu` | contract | §1.4, §1.6 |
| 001.eu-load-twice | — | loading the unit TWICE under `set -eu` is a no-op (the re-source guard) | contract | §1.4 |
| 001.eu-fail | run | a FAILING tool under `run` does not abort a `set -eu` caller | contract | **C12** — `"${argv[@]}" \|\| rc=$?`, never bare |
| 001.eu-missing | run | a MISSING tool under `run` does not abort a `set -eu` caller either | contract | **C12**, **C15** |
| 001.eu-happy | all | the whole happy path runs under `set -eu` | contract | §1.3 |
| 001.eu-badcall | argv | a malformed CALL (bad out-name) does not abort a `set -eu` caller | contract | §1.2 |
| 001.stub-gone | all | no member answers the `__TUTIL_PENDING__` sentinel any more | contract | **C23**, §5 P1.1 |
| 001.stub-source | — | the string `__TUTIL_PENDING__` is not in the unit source at all | contract | **C23** |
| 001.members-real | all | every declared member exists as a real body — none is a bare rc 2 stub | contract | §1.2 |

## 002_Sinks.sh — the five sinks through TPipe (P1) — 56 cases

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 002.u1-fn | each | `TUtil.new u printf '%s\n' a b; u.each cb` delivers 2 records to a plain function | contract | **U1** |
| 002.u1-instance | each | the same through an INSTANCE member — the object's mutations survive | contract | **U1** — the whole point of the `--` form |
| 002.each-proc | each | `each` is a PROC: it answers with its rc alone and leaves the caller's `RESULT` | contract | §2.3 — `kk._invoke` restores RESULT when a body never calls `kk._return` |
| 002.cb-rc1 | each | a callback whose own rc is 1 does not tear the stream down | contract | **D2** |
| 002.each-lastrc | each, lastRc | `each` sets `lastRc` to the producer's RAW status | contract | §2.3 |
| 002.u8-toarray | toArray | RESULT = the count, rc 0, the caller's array replaced | contract | **U8** |
| 002.u8-tolist | toList | RESULT = records offered, rc 0 | contract | **U8**, **C21** |
| 002.u8-first | first | RESULT = the first record, rc 0 | contract | **U8** |
| 002.u8-count | count | RESULT = the number of records, rc 0 | contract | **U8** |
| 002.u8-cmdsubst | toArray, toList, first, count | under `$( )` each func sink prints its value EXACTLY ONCE | contract | **P1-F1** — without `__TPIPE_QUIET` it was twice ([docs §3.6](docs/TUtil.md#36-p1-f1--__tpipe_quiet-and-why-a-redirect-is-not-the-fix)) |
| 002.u8-pipe | toArray, toList, first, count | on the LHS of a pipe the value is printed exactly once too | contract | **P1-F1** |
| 002.each-cmdsubst | each | `each` under `$( )` carries ONLY what the callback printed | contract | **P1-F1** — a `>/dev/null` "fix" would have eaten this |
| 002.each-pipe | each | `each` on the LHS of a pipe carries ONLY what the callback printed | contract | **P1-F1** |
| 002.tolist-printing | toList | a PRINTING `.Add` still reaches stdout, and the count prints once | contract | **P1-F1** |
| 002.u8-mapped-rc | all four | rc = the MAPPED rc, under `$( )` as well as direct (producer exits 3) | contract | **U8**, **C5** |
| 002.argv-handover | argv | `argv` hands over exactly what the sinks will run | cross-check | §2.2 — the premise of every comparison below |
| 002.xc-toarray | toArray | `toArray` == `TPipe.toArray` on the exotic producer, byte-exact, 9 records | cross-check | §2.3 |
| 002.xc-count | count | `count` == `TPipe.count` on the same argv | cross-check | §2.3 |
| 002.xc-first | first | `first` == `TPipe.first` on the same argv (a record starting with `-n`) | cross-check | §2.3, representation |
| 002.xc-each | each | `each` == `TPipe.each` on the same argv: same records, same order | cross-check | §2.3 |
| 002.xc-tolist | toList | `toList` == `TPipe.toList` on the same argv | cross-check | §2.3 |
| 002.nul-frames | toArray | `nul = 1` frames NUL-terminated records — a record with a space stays ONE record | representation | §2.3 |
| 002.nul-equals | toArray | `nul = 1` equals `TPipe` called with `-0` on the same argv | cross-check | §2.3 |
| 002.nul-off | toArray | `nul = 0` (the default) reads the SAME bytes as one truncated record | boundary | §2.3 — the framing is the caller's decision |
| 002.crlf-strip | toArray | `crlf = 1` strips ONE trailing CR per record; `crlf = 0` keeps it | representation | §2.6, **C8** |
| 002.crlf-all | each, first, count | `crlf = 1` reaches `each`, `first` and `count` too | contract | §2.3 |
| 002.three-frame | each | `g.each → TPipe.each → r.onLine`: the callee instance keeps every mutation | contract | §2.3 |
| 002.nested-sink | each | a NESTED sink started from inside the callback does not disturb the outer one | boundary | §2.3, tpipe F13 |
| 002.nested-lastrc | lastRc | the outer instance's `lastRc` is its own, not the inner sink's | boundary | §2.3 |
| 002.fork-cb | each | the callback runs in THIS process for every record (`$BASHPID`) | contract | §1.5 — forks in hot paths are forbidden |
| 002.fork-producer | toArray, count, first | the ONLY fork per call is the producer: 5 records, one foreign pid | contract | §1.5 |
| 002.reject-add | toList | THashSet duplicates: RESULT counts records OFFERED, the set keeps fewer | boundary | **C21** |
| 002.dev-count | count, lastRc | a producer exiting 3: `count` is rc 1, RESULT = 2, `lastRc` = 3 | contract | **C11**, §2.4 — the named deviation |
| 002.dev-toarray | toArray | the same for `toArray` — the array still holds what arrived | contract | **C11** |
| 002.dev-each-tolist | each, toList | the same for `each` (rc 1) and `toList` (rc 1, records offered) | contract | **C11** |
| 002.first-fail-hit | first | `first` on a failing producer that DID give a record is rc 0 — we stopped it | boundary | §2.3 — the consumer-stop path |
| 002.first-fail-empty | first, lastRc | a producer that fails WITHOUT writing: rc 1, RESULT `''`, `lastRc` 4 | boundary | §2.3 |
| 002.first-ok-empty | first, lastRc | a producer that SUCCEEDS without writing: `first` is still rc 1 with RESULT `''` | boundary | §2.3 — "no record" is `first`'s own answer |
| 002.first-silent | first | `first` stays SILENT on the no-record path when the raw rc is not 127 | contract | §1.2 |
| 002.u6-stop | each, lastRc | `each` + `TPipe.stop` on an INFINITE producer: rc 0, `lastRc` 141/143, no hang | contract | **U6**, §2.3 |
| 002.u6-finite | each | the stop is not a failure — the same callback over a FINITE producer is rc 0 | contract | **U6** |
| 002.u6-first | first | `first` on an infinite producer answers at once and does not hang | perf | **U6** |
| 002.bad-cmd-all | all five | `cmd=''`: every sink is rc 2, RESULT `''` for the funcs, and NOTHING runs | contract | **U4** |
| 002.bad-cmd-stdin | all five | `cmd=''`: a here-string handed to a refused sink is still fully readable | contract | **U4** — rc 2 does not touch stdin |
| 002.miss-all | all five | a MISSING command: every sink is rc 1, `lastRc` 127, and NOTHING runs | contract | **U5**, **C15** |
| 002.miss-quiet | all five | a MISSING command is COMPLETELY silent with the switch off | contract | **C15** |
| 002.miss-one | all five | a MISSING command prints EXACTLY ONE line per sink under the switch | contract | §1.2 |
| 002.bad-cb | each | a CB that is not a function: rc 2, nothing runs, `lastRc` UNTOUCHED | contract | §2.5 (TPipe's operand rule), §1.2 |
| 002.bad-inst | toList | an INST without `.Add`: rc 2, RESULT `''`, `lastRc` untouched | contract | §2.5 |
| 002.bad-out | toArray | a bad out-name: rc 2, RESULT `''`, `lastRc` untouched, nothing runs | contract | §1.7 |
| 002.out-own-argv | toArray | `toArray __tu_v` does NOT reach the instance's own argv array | contract | **P1 review** — the check TPipe cannot make |
| 002.two-inst | all five | two instances interleaved keep SEPARATE `_lastRc` | contract | §2.3 |
| 002.argv-still-nothing | argv | `argv` still RUNS NOTHING now that the sinks exist | contract | §1.2 |
| 002.sink-rebuild | all five | a sink REBUILDS the argv: a changed `cmd` is used on the next call | contract | §2.2 |
| 002.three-forms | run, each | `u.run \| TPipe.each cb` under `lastpipe` == the `--` form == `u.each cb` | cross-check | §3 — the three forms |
| 002.producer-in-pipe | run | the wrapper as a producer inside a pipeline: `u.run \| wc -l` is the tool's stream only | contract | §1.1 deviation |

## 003_Contract.sh — the kcl contract for the sinks (P1) — 47 cases

Section 1 runs each case in a CHILD script under `set -eu` with the unit freshly
sourced, so an abort fails the case instead of the file; the child must end rc 0,
print exactly `OK`, and write **nothing** to stderr.

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.parse | — | the unit source parses (`bash -n`) | contract | §4 |
| 003.openquote | — | no single-quoted `printf` format is left open at end of line | contract | §4 |
| 003.inline-cr | — | no member body carries an inline `$'\r'` | bash-convention | §6 — it does not survive the `declare -f`/`eval` round trip |
| 003.eu-load | — | the unit loads under `set -eu` | contract | §1.4 |
| 003.eu-load2 | — | it loads TWICE (both re-source guards hold) | contract | §1.4 |
| 003.eu-each-ok | each | a succeeding tool | contract | §1.3 |
| 003.eu-toarray-ok | toArray | a succeeding tool | contract | §1.3 |
| 003.eu-tolist-ok | toList | a succeeding tool | contract | §1.3 |
| 003.eu-first-ok | first | a succeeding tool | contract | §1.3 |
| 003.eu-count-ok | count | a succeeding tool | contract | §1.3 |
| 003.eu-each-3 | each | a tool exiting 3 — the child survives and the member is rc 1, never the tool's 3 | contract | **C12**, §2.4 |
| 003.eu-funcs-3 | toArray, toList, first, count | a tool exiting 3 — rc 1, the records KEPT | contract | **C11** |
| 003.eu-cb-rc1 | each | a callback answering rc 1 on EVERY record does not abort | contract | **D2** |
| 003.eu-stop | each | `TPipe.stop` on an INFINITE producer: rc 0 and no hang | contract | **U6** |
| 003.eu-first-inf | first | `first` on an INFINITE producer: rc 0 and no hang | contract | **U6** |
| 003.eu-reject-add | toList | a REJECTING `.Add` (THashSet duplicates) does not abort | boundary | **C21** |
| 003.eu-cmd-empty | all five | `cmd=''` — every sink is rc 2 with RESULT `''`, `lastRc` still `-1` | contract | **U4** |
| 003.eu-missing | all five | a missing command — every sink is rc 1 with `lastRc` 127 | contract | **U5** |
| 003.eu-malformed | each, toArray, toList | a malformed CB / out-name / list is rc 2 and leaves `lastRc` alone | contract | §1.2, §1.7 |
| 003.eu-cmdsubst | count, first | the sinks under `$( )` answer with their value and do not abort | contract | **P1-F1** |
| 003.fork-eu | each | every callback call happens at the child's own `$BASHPID`, under `set -eu` | contract | §1.5 |
| 003.dbg-each-empty | each | `cmd=''` is rc 2 and exactly ONE line | contract | §1.2 |
| 003.dbg-toarray-empty | toArray | `cmd=''` is rc 2 and one line | contract | §1.2 |
| 003.dbg-tolist-empty | toList | `cmd=''` is rc 2 and one line | contract | §1.2 |
| 003.dbg-first-empty | first | `cmd=''` is rc 2 and one line | contract | §1.2 |
| 003.dbg-count-empty | count | `cmd=''` is rc 2 and one line | contract | §1.2 |
| 003.dbg-bad-cb | each | a CB that is not a function is rc 2 and one line | contract | §1.2 |
| 003.dbg-out-reserved | toArray | a reserved out-name (`RESULT`) is rc 2 and one line | contract | §1.7 |
| 003.dbg-out-own | toArray | the instance's own `_argv` is rc 2 and one line | contract | §1.7 |
| 003.dbg-out-prefix | toArray | this family's `__tu_` prefix is rc 2 and one line | contract | §1.7 |
| 003.dbg-no-add | toList | an INST with no `.Add` is rc 2 and one line | contract | §2.5 |
| 003.dbg-miss-each | each | a missing command is rc 1 (`lastRc` 127) and one line | contract | **C15** |
| 003.dbg-miss-toarray | toArray | a missing command is rc 1 and one line | contract | **C15** |
| 003.dbg-miss-tolist | toList | a missing command is rc 1 and one line | contract | **C15** |
| 003.dbg-miss-first | first | a missing command is rc 1 and one line | contract | **C15** |
| 003.dbg-miss-count | count | a missing command is rc 1 and one line | contract | **C15** |
| 003.silent-each-ok | each | a successful run says NOTHING under the switch | contract | §1.2 |
| 003.silent-toarray-ok | toArray | a successful run says NOTHING | contract | §1.2 |
| 003.silent-tolist-ok | toList | a successful run says NOTHING | contract | §1.2 |
| 003.silent-count-ok | count | a successful run says NOTHING | contract | §1.2 |
| 003.silent-first-ok | first | a successful run says NOTHING (the producer's own stderr discarded) | contract | §1.2, §4 |
| 003.silent-each-1 | each | a plain rc 1 (tool exited 3) says NOTHING | contract | §2.4 |
| 003.silent-toarray-1 | toArray | a plain rc 1 says NOTHING | contract | §2.4 |
| 003.silent-tolist-1 | toList | a plain rc 1 says NOTHING | contract | §2.4 |
| 003.silent-count-1 | count | a plain rc 1 says NOTHING | contract | §2.4 |
| 003.dbg-names-member | all five | the `127` line names the MEMBER that was called, not just `run` | contract | **C15** — the diagnostic must send the reader to the right place |
| 003.d6-warn | toArray | the `--` form under `$( )` warns ONCE under the switch and is silent without it | contract | **D6** |

## 004_Bench.sh — the P3.1 performance gates (P3) — 8 cases

The real gates are measured by `../bench.sh` on an idle machine (README §6);
this file asserts the same shapes with a **5×** ceiling, because ktests runs test
files threaded with 8 workers and the same two cases have been seen at 0.94× and
1.87× under that load. N = 2000 here, not 10 000.

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.gate-each | each | `u.each` + a no-op function costs at most 5× `TPipe.each` called DIRECTLY on the same argv, and delivers the same N records with rc 0 | perf | §5 P3.1 — the delegation is one prologue per CALL and zero work per record (idle: 0.97× / 1.00×) |
| 004.gate-toarray | toArray | `u.toArray` costs at most 5× `TPipe.toArray` direct, with the same count and the same first and last record | perf | §5 P3.1 (idle: 1.05× / 0.95×) |
| 004.argv-runs-nothing | buildArgv, argv | 200 `buildArgv`/`argv` calls invoke the `cmd` (a counting function) ZERO times, leave `$BASHPID` unchanged, and hand over the 6 expected words | contract | §1.2, §1.5 |
| 004.argv-constant | argv | the build stays constant-cost: after 200 rebuilds the argv is still 6 words | boundary | §2.2 |
| 004.fork-each | each | the callback runs in THIS process for every record | contract | §1.5 |
| 004.fork-tolist | toList | `.Add` runs in THIS process for every record | contract | §1.5 |
| 004.fork-producer | toArray, count, first | the ONLY fork per call is the producer — 5 records, one foreign pid, and `count`/`first` agree | contract | §1.5 |
| 004.fork-run | run + the six builder members | the `cmd` that `run` executes reports THIS process's `$BASHPID` (a function cmd is not forked), rc 0 / `lastRc` 0, and `buildArgv`/`argv`/`addArg`/`clearArgs`/`mapRc`/`lastRc` leave `$BASHPID` untouched | contract | §1.5, §2.3 |
