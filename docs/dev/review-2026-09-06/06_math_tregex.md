# Reviewer report G4 — math / tregex (2026-09-06)

Repro scripts: `repro/g4/m1.sh … m7.sh` (math), `t1.sh … t4.sh` (tregex).

### Summary
Both units pass their suites on both bashes: **math 81/81**, **tregex 190/190**. tregex is in good shape — the =~/BASH_REMATCH plumbing, nocasematch save/restore, escape round-trips, empty-match advance and the `$`-replacement grammar behave as documented; its real defects are `set -e` incompatibility, an arithmetic-injection path through `maxCount`, and a wrong locale claim. math's Tier-A core is solid, but the awk float engine has serious lifecycle holes: (1) any awk fatal (division by zero — `fmod x 0`, `cotan 0`, `csc 0`, `logN 1 x`, `mean` with no args, `intPower 0 -1`, …) kills the co-process and the call returns an empty line with rc 0; (2) `frexp` of `inf`/`nan`/≥1e308 hangs the caller forever; (3) an argument containing a newline desynchronises the request/answer pipe permanently.

### Findings — math

**M1 | HIGH | math.sh:145,160-162,175-181,113,192-195,99,143-144,204 (awk prelude) + :493-497 | Division by zero (any awk fatal) kills the engine silently; call returns empty + rc 0**
gawk aborts on float division by zero, so the co-process dies; `_fe`'s `read` hits EOF, the method echoes an empty line and returns 0. The next Tier-B call respawns awk and bash prints `warning: execute_coproc: coproc [pid:MATH_FE] still exists`.
Repro: `bash m1.sh` → `fmod 5 0 -> [] rc=0`, then `feActive=false`; same for `cotan 0`, `csc 0`, `arcSec 0`, `arcCotH 1`, `logN 1 5`, `intPower 0 -1`, `power 0 -1`, `mean` (no args), `popnVariance` (no args), `payment 0 0 1 1`, `numberOfPeriods 0 0 1 1`, `roundTo 1 -400`, `simpleRoundTo 1.5 400`.
FPC: EZeroDivide/EInvalidArgument or ±Inf/NaN. Fix: guard every `/` in the prelude (return `inf`/`nan` tokens), and make `_fe` propagate failure with the public wrappers returning that rc (R11).

**M2 | HIGH | math.sh:111 (`_frexp`) + :496 | `frexp inf|nan|1e308` hangs the calling shell forever**
Repro: `timeout 5 bash -c 'source math.sh; math.frexp 1e308'` → rc 124 (also `+inf`, `nan`). Expected `frexp(1e308)` = `0.55… 1024`. Fix: special-case 0/inf/nan; use `int(log(x)/log(2))` with bounded correction; `read -t` in `_fe`.

**M3 | HIGH | math.sh:495 | Newline in any argument desynchronises the pipe permanently**
`printf '%s\n' "$*"` sends two request lines; the second answer is returned by the NEXT call, forever.
Repro (`m1.sh` "newline desync"): `math.sin $'0\n2'` then `math.cos 0` → `[ERR]`, then `math.cos 0` → `[1]`... Fix: reject/strip `\n` before writing.

**M4 | HIGH | math.sh:637-638 (divMod), 760 (sumInt), 556-557 (min/maxIntValue), 777-780 (randomRange), 443-444 (`_num_cmp` fast path) | Raw arguments go into `$(( ))`: code injection, and `08`/`09` crash**
Repro: `math.divMod 'a[$(echo INJECTED >&2)]' 1` → prints INJECTED twice; `math.min 08 5` → `((: 08: value too great for base`; `math.minIntValue 08 5` → `08`. Fix: `kk.isInt` + `10#`.

**M5 | MED | math.sh:69-71, 137-141, 793-794; README "Conventions", PLAN.md:55,93 | The unit's own `inf`/`nan` tokens are read as 0 by gawk; engine actually emits `+inf`/`-nan`**
Repro (`m3.sh`): `math.max "$(math.infinity)" 1` → `1`; `math.sign inf` → `0`; `math.isZero inf` → `true`; `math.sameValue inf inf` → `true` (0==0); `math.ceil inf` → `0`; `math.max +inf 1` → `+inf`. Fix: normalise in `_fe` (R11).

**M6 | MED | math.sh:474-475, 499-506; README ("the temp file is auto-cleaned") | Program temp file leaks once per process (no EXIT trap)**
Repro: `bash -c 'source math.sh; math.sin 1'`; `ls /tmp/.math_fe_*.awk` → file remains. Fix: process substitution or EXIT trap chain (R11).

**M7 | MED | math.sh:421 (`_trunc`), 407 (`_dec_cmp`), 444 (`_num_cmp`) | Tier-A calls abort the caller under `set -e`**
Repro: `set -e; math.min 1.5 2; echo x` → exits rc 1. Fix: terminate helpers with `return 0` / use `if`.

**M8 | MED | math.sh:659-660 (intPower), 760 (sumInt) | Silent 64-bit wraparound on the "exact" pure-bash paths**
`math.intPower 2 63` → `-9223372036854775808`, `2 64` → `0`; `math.sumInt 9223372036854775807 1` → negative. Fix: bound-check and fall through to the engine `ipow`.

**M9 | MED | math.sh:476 | `coproc MATH_FE` prints a bash warning whenever the engine is (re)started while a coproc exists** — Fix: `wait "$__MATH_FE_PID"` before respawning; document the one-coproc caveat.

**M10 | LOW | math.sh:691-771 wrappers; README "No awk?" | With no awk, public Tier-B methods echo an empty line and return 0, not "non-zero"** — `( PATH=; math.sin 1; echo rc=$? )` → blank, `rc=0`.

**M11 | LOW | math.sh:143-144 | `roundTo`/`simpleRoundTo` return `-0`** — `math.roundTo -0.4 0` → `-0`.

**M12 | LOW | math.sh:548-549, 589, 789 | `echo "$1"` swallows `-n`/`-e`; `ifThen c x ""` yields `0`** — `${3:-0}` treats explicit empty as absent.

**M13 | LOW | math.sh:775-781 | `randomRange` is 30-bit and overflows for wide ranges**.

**M14 | LOW | math.sh:443-451, awk prelude | Non-numeric operands silently accepted** — `math.min abc 5` → `5`, `math.sqrt abc` → `0`, `math.ceil 0x10` → `0`, `math.sin "1 2"` → sin(1). Fix: `math._is_num` gate (`kk.isNum`).

**M15 | LOW | math.sh:124-204 | Locale decimal separator: safe only in gawk's default mode** — `POSIXLY_CORRECT=1` or `--use-lc-numeric` makes gawk print `2,5`. Fix: `LC_ALL=C awk …`.

### Findings — tregex

**T1 | MED | tregex.sh:136-137, 242, 288, 373 | Every member except `escape` aborts the caller under `set -e`**
`[[ … =~ … ]] 2>/dev/null` as a statement fails on no-match; `(( __trx_count++ ))` returns 1 on the first increment.
Repro (`t1.sh`, `t2.sh`): `set -e; a=(); TRegEx.matches "a1b2" "[0-9]" a; echo …` → exits rc 1; `TRegEx.replace "a1b2" "[0-9]" "#"` direct → rc 1; `TRegEx.match "abc" "x"` → rc 1. Fix: `if [[ … ]]; then rc=0; else rc=$?; fi`, and `(( x += 1 ))`.

**T2 | MED | tregex.sh:278, 361 (also 269, 352) | `maxCount` is evaluated arithmetically unvalidated → code injection**
`TRegEx.split "a,b,c" "," p 'x[$(echo INJECTED >&2)]'` → prints INJECTED (twice). Fix: `kk.isInt`.

**T3 | MED | tregex.sh:41-45 (S9), docs/ERE-vs-PCRE.md §5, README "Match offsets"; tests/003_Match.sh:40-46 | Under the empty/C locale the regex engine matches BYTES; the docs claim the opposite**
Repro (LANG/LC_ALL empty): `TRegEx.match "héllo wörld" "w.rld"` → rc 1, `RESULT_INDEX=-1`; `LC_ALL=C.UTF-8` → `wörld`, idx 6, len 5. Fix: rewrite S9/§5; add a `.`-on-multibyte test under both locales (D6).

**T4 | MED | tregex.sh:244, 290, 375-377; :36-38 (S6) | Zero-length anchored patterns (`$`, `\b`, `\<`, `\>`) produce len+1 spurious matches in `matches`/`replace`/`split`**
Repro (`t2.sh`): `TRegEx.matches "abc" '$' a o` → n=4, offsets `0 1 2 3` (.NET: 1 at 3); `TRegEx.matches "ab cd" '\b' a o` → n=5; `TRegEx.replace "abc" '$' '!'` → `!a!b!c!` (.NET `abc!`). Fix (R12): correct S6/§4 and pin the cases now; detection only if a `\b` consumer appears.

**T5 | LOW | tregex.sh:135 | Flags parsed with `*i*` — any flag word containing `i` turns on case-insensitivity** — `TRegEx.isMatch "ABC" "abc" Multiline` → rc 0.

**T6 | LOW | tregex.sh:194-199 | `escape` is O(n²)** — 50 000 chars 14.3 s. Fix: 14 `${s//x/\\x}` substitutions (backslash first).

**T7 | LOW | tregex.sh:246, 292, 382 | Scans copy the remainder per match → O(n·k)** — `replace` with 4000 matches in 12 kB: 2.1 s.

**T8 | LOW | tregex.sh:225, 228, 267; README "Reserved array names" | Invalid/reserved output-array names fail loudly but rc stays 0; reserved list incomplete** — `TRegEx.matches "abc" "b" "1bad"` → bash error, rc 0, RESULT=1. Fix: `local -n … 2>/dev/null || { RESULT=0; return 2; }`; list `__tre_g`/`__tre_m`/`__tre_rc`.

**T9 | LOW | README | `$()` capture strips trailing newlines of `replace`/`escape` results** (RESULT keeps them). Document.

**T10 | LOW | tregex.sh:322-326 | `$10`/`$11` are read as `$1`+`0` even when group 10+ exists** (`${10}` works).

### Test gaps
- math: no test for any engine-fatal input (M1); no test that a public Tier-B method returns non-zero on engine failure; no `frexp` of `inf`/`nan`/`1e308` (M2); no argument-with-newline/space/garbage/hex/`08` tests (M3, M4, M14); no injection test on `divMod`/`sumInt`/`randomRange`; `inf`/`nan` tokens never fed back into `min`/`max`/`sign`/`ceil` (M5); temp-file cleanup untested and every test file calls `_fe_stop` (M6); no `set -e` smoke (M7); `intPower`/`sumInt` overflow boundary (M8); `-0` output (M11); `randomRange` > 2^30 (M13); `%.17g` output never asserted for locale (M15); `roundTo` negative tie and `digits>0` cases unasserted.
- tregex: no `set -e` test (T1); no non-numeric/negative `maxCount` (T2); multibyte test uses a literal-byte pattern (T3); zero-length anchored scans only pin `^` (T4); no unknown-flag test (T5); no large-input perf guard for `escape` (T6); no invalid nameref-name test (T8); no `$10`/`${10}` with ≥10 groups (T10); no test that a `replaceCb` callback calling `TRegEx.*` inside `_replaceScan` is unsupported (it clobbers the in-scope `__tre_g`).
