# Changelog — kcl

> Draft (launch L6.7): reviewed before the first release (L8).

kcl is the class library of kbool: bash ports of Free Pascal / Delphi units
(`TList`, `TStringList`, `TDictionary`, `TIniFile`, `TPath`, `TRegEx`, ...) and
wrappers around GNU command-line tools (`TGrep`, `TSed`, `TAwk`, ...). There is no tag or
release yet; this file groups the whole history by phase, newest first. The
unit list and the contract every unit meets are in [README.md](README.md).
Commit hashes in parentheses point at the change for readers who want the diff.

## Unreleased — first public release (draft)

### CI and the bash 5.1 floor (2026-10-29 .. 2026-10-30, launch L4.5, L5.4, L5.6, L5.7)

* The minimum bash is now **5.1** (was 5.2): unquoted file-descriptor redirect
  targets in `math`, `thttpmessage` and the benches were rewritten, and a static
  check (`tests/002_Bash51Hazards`) keeps 5.1-hostile constructs out (b59b370).
* **TRegEx**: `\<`, `\>` and `\b` work on every C library. Where the library does
  not spell a word edge, TRegEx rewrites it; where the right rewrite depends on
  context and cannot be decided (macOS), the pattern is rc 2 instead of a silent
  wrong answer (cfd6802, 21c9aeb).
* **math**: the engine start probe can no longer kill its caller with SIGPIPE
  when the awk co-process dies at start (df09a88).
* Tests call `"$KT_TIMEOUT"` and report SKIP, not FAIL, on a machine with neither
  `timeout` nor `gtimeout`; a tregex locale case no longer breaks on macOS runners.
* CI: kcl has its own workflow that runs the 13-row kbool matrix with this
  commit as kcl (6306e33); `CONTRIBUTING.md` added (40b61dc).
* **TGrep** gains `quiet` (`-q`), `TGrep.contains TEXT PATH...` (rc only) and
  `TGrep.countMatching TEXT PATH...` (RESULT = matching lines); **TFind** gains
  `TFind.quoteGlob TEXT` (a literal `-name` / `-iname` pattern). Literal text in,
  no regex or glob syntax for the caller to escape (launch L6.0, HELPERS_PLAN H2).

### Other platforms: Alpine, FreeBSD, GNU tool resolution (2026-10-26 .. 2026-10-29, launch L3, L3.4)

* **Wrappers find their GNU tool through `ktool`** (kkore): `TUtil`, `TSed`, `TAwk`,
  `TGrep`, `TFind`, `THead`, `TTail` resolve an absolute path (`ggrep`, `gfind`,
  `gsed`, `gawk`, ... on FreeBSD); with no usable tool every sink answers rc 2 with
  the reason. uutils `head`/`tail` from 0.2.2 are accepted.
* **TFile**: `encrypt`/`decrypt` use a new encrypt-then-MAC format (`KBTF1`,
  HMAC-SHA256), so a wrong password or tampered data is always detected.
  **Breaking:** files written by the earlier format are refused (c765adc).
* **TPipe** recovers the exit status of process-substitution producers that bash
  loses under load, external producers included; the status line is tagged (b9b6ec3,
  2d63608).
* **TPath**: portable time, attribute and path helpers for busybox and BSD
  (`getFullPath` keeps `realpath -m` where it exists and normalises lexically
  elsewhere); canonical UTC date strings are parsed in bash.
* **math** runs on the BWK awk of macOS/FreeBSD and starts quietly; **thttpserver**
  uses a fresh FIFO per listener and leaves no `sh-np.*` files behind on bashes with
  FIFO process substitution (2da8dac, bdbabff).
* Tests use portable BSD/busybox idioms; the GNU `stat`/`date` oracles moved to
  `tpath/tests/_fsoracle.sh`.

### Linux first: portability and shared contracts (2026-10-20 .. 2026-10-22, launch L0, L2)

* All text files are LF; every script starts with `#!/usr/bin/env bash` and has its
  exec bit (b138394, f5d74f3).
* **One CR contract** for `TUtil`/`TSed`/`TAwk`/`TGrep`: in text mode a script
  never sees the trailing CR of a CRLF line on any platform, as on Windows before;
  `binary=1` keeps it, and a CR a script writes on purpose survives (f8d94bf).
* **TPipe.stop** stops the producer's whole process tree (90dcf55).
* **thttpserver** detects the network backend and never starts a non-GNU netcat with
  GNU flags; a new **TSocatTransport** is chosen automatically where GNU netcat is
  absent (349c2fe, 542de10).
* **math** gets a portable awk engine (`mawk`, `gawk` preferred), NaN/inf guards that
  end an endless-loop hazard, and a co-process that `exec`s awk so a wedged engine
  can be stopped (27c2844, 26d9c6b).
* **TRegEx**: an empty pattern is rc 2 on every engine. **TSed** gains literal-replace
  helpers `addReplace FROM TO [FLAGS]`, `quoteRe`, `quoteRepl` (8928a1b).
* Comma-locale-safe `EPOCHREALTIME` handling in tests and benches (`de_DE`, `ru_RU`).
* Internal plans, ledgers and reviews moved to `docs/dev/` (82057ad).

### Units are kbool units: `kk.uses` (2026-10-12 .. 2026-10-15, uses U4, U5)

* Every kcl unit now carries a unit header and is loaded by name:
  `kk.uses tlist`. Sourcing the file directly still works (dbb7538 .. 6ecb74e).
* `math` engine state no longer trusts the environment (251094a).
* `kcl/tests` checks that every unit meets the unit shape; README documents the
  header rule (1c94f0e).
* Temp hygiene and suite wrappers (d6acafa).

### kklass round follow-ups (2026-10-02)

* The `$this.NAME` text rewrite is gone from kklass; kcl wording and
  `thttpserver` internals follow (`kk.isAbstract` / `kk.derivesFrom` replace
  reaching into kklass internals).

### thttpserver and timing-test hygiene (2026-09-26 .. 2026-09-30)

* **thttpserver** (P0-P3, 1cc2d57): a minimal HTTP server on kklass: `THttpRequest`,
  `THttpResponse`, `THttpRouter`/`THttpRouteObject`, `THttpServer` over a pluggable
  transport (`TReplayTransport` for tests, `TNetcatTransport` with two pre-spawned
  slots) and `THttpApplication : TCustomApplication`; examples, bench, docs.
* A post-completion review closed six findings (F1-F6).
* Timing tests no longer fork inside timed windows (71f22d1); `ttail` follow tests
  have hang guards.

### CLI-tool wrapper family (2026-09-10 .. 2026-09-24)

* **TPipe**: a stream-to-callback adaptor (`each`, `stop`, `lastRc`, sinks `toArray`,
  `toList`, `first`, `count`, `-0`/`-c`). Final design: no refusals in subshells,
  warnings through `kk.warn`.
* **TUtil**: the base class for command-line wrappers (typed options into a pinned
  argv, `run`, `mapRc`, sinks through TPipe).
* **TGrep** (GNU grep, 22 typed options), **THead** and **TTail** (coreutils, with
  `follow`), **TFind** (findutils), **TSed** (sed, `expr`/`addExpr`/`scriptFile`) and
  **TAwk** (gawk 5.0 and 5.4, `program`/`addProgram`/`programFile`, `setVar`).
* Every wrapper has a README, benches, coverage notes and tests.

### thashset (2026-09-09)

* **THashSet** (P0-P4): FPC `THashSet` with set algebra (`UnionWith`, `IntersectWith`,
  `ExceptWith`, `SymmetricExceptWith`, `AddRange`), notification events
  (`onNotify`, destroy fires `removed`), bench and docs.

### Deep review of all units, P0-P10 (2026-09-06 .. 2026-09-09)

* The review (`docs/dev/REVIEW.md`) found three error conventions and five boolean
  conventions across the corpus; the **kcl contract** (README section 1) fixed one:
  results in `RESULT`, errors as rc 1 with silent stderr, rc 2 for malformed calls,
  exact numeric guards, `set -eu` safety, locale-exact parsing, no forks in hot
  paths (61ea0ee).
* P1 cross-unit hardening; P2 containers (`tlist`, `tobjectlist`, `tstringlist`,
  `tarray`, `thashset`, `tqueuestack`, `tdictionary`); P3 file system (`tpath`,
  `tfile`, `tdirectory`: separators, symlinks, setters); P5 `tstringhelper` (FPC
  semantics, O(n) paths); P6 `dateutils` and `tstopwatch` (numeric boundaries,
  ISO/Julian parity, DST-aware offsets); P7 `math` and `tregex` (engine lifecycle,
  flags, escape); P8 `tinifile` (persistence safety, write-side validation).
* **TCustomApplication**: the option parser is now a line-by-line port of FPC 3.2.2
  `custapp.pp` (6afbc8d); option handling now follows FPC where the earlier
  hand-written parser differed.
* Unit table with contract status, docs headers and ledger statuses (P9); the
  `fpjson` plan was rewritten (P10); the remaining open findings were closed by
  owner decisions (125f768).

### FPC / Delphi ports (2026-07-11 .. 2026-07-18)

* **dateutils** (FPC `DateUtils`, 185 members), **math** (FPC `Math`, 123 members,
  pure-bash core plus an awk float engine), **tdictionary** (`TDictionary`,
  `TObjectDictionary`), **tstopwatch** (Delphi `TStopwatch`).
* **tregex**: a `TRegEx`-shaped API over bash `[[ =~ ]]` ERE. **tarray**: sort,
  binary search and scan helpers; `TList`/`TStringList` delegate sorting to it, and
  `TList.Sort` with no argument is a byte-order sort.
* **tobjectlist** (the owning list), **tinifile** (`TIniFile`, `TMemIniFile`),
  **tqueuestack** (`TQueue`, `TStack`, `TObjectQueue`, `TObjectStack`).
* Classes were ported to the Pascal DSL (7dde59c); benches use the shared
  `TStopwatch` clock.

### Hardening (2026-07-08)

* A security and performance pass over the whole class library (bfa1f26).

### Foundations (2025-10-30 .. 2026-05-26)

* First units: **tpath**, **tstringhelper** (named `tsringhelper` for its first week),
  **tdirectory**, **tfile**, **tlist**, **tstringlist**, **tcustomapplication**
  (with `getopts`, `OptionChar`, argument caching).
* `eval` was removed from `tlist` and `tcustomapplication`.
* Tests were split into numbered per-case files and moved onto the ktests framework;
  performance passes on list and string-list operations (adaptive growth, no
  array copies, no external grep/sed).
