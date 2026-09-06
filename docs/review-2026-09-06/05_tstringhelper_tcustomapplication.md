# Reviewer report G7 — tstringhelper / tcustomapplication (2026-09-06)

Repro scripts: `repro/g7/tsh_repro.sh`, `tca_repro.sh`, `loc.sh`.

### Summary
Both suites are green on bash 5.2.37 — tstringhelper 393/393 (59 files), tcustomapplication 320/320 (30 files) — but green mostly because the tests assert on the wrong thing (substring containment, "either of two values", `$? -eq 0`, guarded-by-`ParamCount>0`) or enshrine non-FPC behaviour. tstringhelper: three systemic defects (arithmetic injection through every index/count parameter, `echo` swallowing `-n`/`-e` data, byte-vs-char semantics depending on the caller's locale — in the default/test environment it is bytes and `${s,,}` corrupts UTF-8 on 5.2). tcustomapplication's option parser diverges from FPC's `custapp` core contract (`--opt=value`, `:`/`::` value options, `CaseSensitiveOptions`, `AllErrors` all unsupported or ignored), `ParamCount`/`Params` return garbage, and the "auto-initialize from script parameters" path stores the *method's own arguments* as the application's argv. TSH-01/02/03/06/10 also confirmed on 5.3.9.

### Findings — tstringhelper (`tstringhelper.sh`)

`TSH-01 | HIGH | :694,696,228,230,351-356,335-338,259-262,279-282,370-375,398-407,420-433,476-489,503-514,655,835-836 | Index/count params evaluated arithmetically → command execution`
`${self:$startIndex}`, `[[ $index -le 0 ]]`, `local i=$startIndex; (( i + val_len ))` etc. Repro: `string.substring hello 'a[$(touch M)]'` creates M; same for remove, insert, chars, isDelimiter, padLeft/padRight, indexOf/indexOfAny/indexOfAnyUnquoted (startIndex/count), lastIndexOf/lastIndexOfAny, create. `toCharArray`/`copyTo`/`_parse_int` already validate. Fix: `kk.isInt` guard (D1).

`TSH-02 | HIGH | :605,694,781,797,809 (all ~40 echo-style bodies) | echo swallows results that look like echo options`
`string.trim " -n "` → `""`, `string.copy -n` → `""`, `string.toUpper -e` → `""`, `string.substring "-name" 0 2` → `""`. Fix: `printf '%s\n'` / RESULT idiom (D3).

`TSH-03 | HIGH | :140-155 | split returns nothing usable and loses data`
Parts are echoed with `${parts[*]}` = re-joined by the separator: `split 'a,b,c' ','` → `a,b,c` (== input), `split 'a b,c' ','` → `a b,c` (ambiguous). `read` stops at the first newline: `split $'a,b\nc,d' ','` → `a,b` (c,d lost). Multi-char sep is a char set (`', '` on `'a, b'` → `a,b`). No Quote/ExcludeEmpty. Test 037 only asserts `*a*` containment. Fix: fill a caller-named array via nameref and return the count; loop with `${rest%%"$sep"*}` (R9).

`TSH-04 | HIGH | :781,797,829,838,694 | Char semantics depend on caller's locale; default (and test) environment is bytes, and 5.2 corrupts UTF-8 on case conversion`
With LANG/LC_ALL unset bash runs in C: `length 日本` → 6, `chars 'мир' 1` → a lone byte, `indexOf 'мир' 'р'` → 4, and on 5.2 `toLower 'ÄÖ'` → `��` (5.3.9 leaves them unchanged), `toUpper café` → `CAFé`. With `LC_ALL=C.UTF-8` all are char-correct. Tests 017/025/028 use non-ASCII only after ASCII prefixes. Fix: decision D6.

`TSH-05 | MED | :211-221 | replace default = first occurrence; FPC/Delphi Replace(Old,New) = rfReplaceAll` — `string.replace 'a-b-c' '-' '+'` → `a+b-c`. Test 036:18 enshrines it. (R9.)

`TSH-06 | MED | :473-498,500-523 | lastIndexOf/lastIndexOfAny: StartIndex exclusive and Count math wrong`
`lastIndexOf hello lo 4` → -1 (FPC 3), `lastIndexOf hello l 3` → 2 (FPC 3), `lastIndexOf hello l 4 5` → -1 (FPC 3). Test 027:64,73 accept either of two values. Fix: `i=startIndex` (default len-1), `min=max(0,startIndex-count+1)`, loop `i>=min`, compare `${str:i:val_len}`.

`TSH-07 | MED | :700-707 | toBoolean only accepts "true"/"1"` — `True`, `TRUE`, `-1`, `2` → false; FPC TryStrToBool is case-insensitive and any non-zero number is true. (R9.)

`TSH-08 | MED | :234-245,661-665 | quotedString/deQuotedString wrong vs FPC and lossy`
Custom quote char not doubled: `quotedString 'say "hi"' '"'` → `"say "hi""`. Default path forks `echo|sed` and drops trailing newlines. deQuotedString strips every `"` anywhere and ignores FPC's default `'`. Fix: `"$q${str//"$q"/$q$q}$q"`; dequote only when both ends are `$q`, then `${inner//$q$q/$q}`.

`TSH-09 | MED | :179-206,433-439,642-646,463-469 | O(n·m) char loops; 10 KB replace/indexOf/countChar take 520–600 ms (5.2), 213 ms (5.3.9)` — `${big//X/Y}` takes 0.36 ms. Fix: `${t%%"$v"*}` for indexOf, `${s/"$old"/$new}` / `${s//"$old"/$new}` for case-sensitive replace, `${s//"$c"/}` for countChar; keep the loop only for rfIgnoreCase.

`TSH-10 | MED | :264,284,655,296 | loop variables not local` — `i=99; string.padLeft x 3 >/dev/null` → `i=2`; `string.join` leaves `arg=b`.

`TSH-11 | LOW | :689-698,223-232 | substring/remove negative or empty indices diverge from FPC Copy clamping` — `substring hello -3` → `llo` (FPC `hello`), `substring hello 1 -1` → `ell` (FPC `""`), `remove hello ''` → `""`.

`TSH-12 | LOW | :805-820 | trim* use [[:space:]]; FPC Trim strips all chars <= #32` — Fix: `[![:space:][:cntrl:]]`.

`TSH-13 | LOW | :424-427 | indexOf('') returns StartIndex (Delphi/.NET); FPC 3.2 returns -1` — tests 017:90,162 pin 0. (R9: FPC.)

`TSH-14 | LOW | :763-777 | toInteger accepts "3.9"→3 (FPC raises), rejects "0x10"/"$10" (FPC → 16); failure prints 0 rc=1 — indistinguishable from "0" under $()`.

`TSH-15 | LOW | :529-533 | format: printf errors surface as "kklass.sh: line 974: printf: abc: invalid number" and return "0"`; Pascal `%0:s` indices unsupported.

`TSH-16 | LOW | :608-635 | copyTo destination named like a local (self/count/char_index) silently no-ops with rc 0`.

`TSH-17 | LOW | :15-23,98-861 | Contract inverted vs the kklass RESULT idiom` — `string.length abc` prints `3`, RESULT/REPLY stay empty; every call forces a `$()` fork. (D3.)

`TSH-18 | LOW | :739-749,789-793,247-249 | toDouble/toExtended/toSingle/parse are pass-through of the first word` — `toDouble abc` → `abc`.

`TSH-19 | LOW | :443-456 | getHashCode differs across locales (byte vs code point)`.

### Findings — tcustomapplication (`tcustomapplication.sh`)

`TCA-01 | HIGH | :199-235,237-258,441-448 | --opt=value (FPC's only long-option value syntax) is not recognised`
`SetArgs -- --config=data.ini`: `GetOptionValue "" config` → `""` (FPC `data.ini`), `HasOption "" config` → false, `CheckOptions "" "config:"` → `Invalid option: --config=data.ini`. Conversely `--out file` returns `file` (FPC: `''`). Tests 025/027/029 enshrine the workaround `verbose=true`. Fix: compare `${arg%%=*}` for long options; value = `${arg#*=}`.

`TCA-02 | HIGH | :419-421,331-346,351-356 | ShortOptions ':'/'::' and LongOpts 'name:'/'name::' are stripped/ignored`
`CheckOptions "c:" ""` on `-c` → `""` (FPC: `Option at position 1 needs an argument : c`); `-cv x` with `c:v` accepted (FPC error: c not last in cluster); `--verbose` with `verbose:` → `Invalid option: --verbose`; values not consumed: `GetNonOptions "c:v"` on `-c cfg.ini -v tail.txt` → 2 (FPC 1). Tests 006/012 pin 3 and 2; 027:96-101 passes either way. Fix: port FPC's CheckOptions loop (HaveArg/UsedArg, `Inc(I)` to skip the consumed value, SErrOptionNeeded/SErrNoOptionAllowed).

`TCA-03 | HIGH | :601-614 | ParamCount/Params read the method call's own $#/${!index}, not the stored arguments`
`TCustomApplication.new a -v file.txt out.txt; a.ParamCount` → 0 (FPC 3); `a.Params 1` → `""`; `a.Params 1 2 3` → `1`. Tests 008:90 and 011 are guarded by `if ParamCount>0`. Fix: `RESULT=${state[_TCUSTAPP_ARGS_COUNT]}`, `RESULT=${state[_TCUSTAPP_ARG_$((index-1))]}` (FPC Params[0]=ExeName).

`TCA-04 | HIGH | :141-159,167-169 + "$@" at :205,242,265,304,390,477 | Without SetArgs, the first option method stores its OWN parameters as argv`
Fresh app: `GetNonOptions "" "" nn` → 3 `['' '' 'nn']`; `CheckOptions "hv" "help" false` then GetNonOptions → `['hv' 'help' 'false']`. Test-019 idiom `app.CheckOptions "hv" "help version verbose" "false" "$@"` "passes" only because those strings don't start with `-`. Fix: remove the `"$@"` forwarding; document `Create "$@"`/`SetArgs "$@"`.

`TCA-05 | HIGH | :616-621 (also :213 start_at) | EnvironmentVariable: ${!var_name} evaluates subscripts → command execution` — `a.EnvironmentVariable 'x[$(touch M)]'` creates M; `'not valid'` prints a bash error with rc 0; `'@'` returns positional params. Fix: validate `^[A-Za-z_][A-Za-z0-9_]*$`; integer-guard start_at.

`TCA-06 | MED | :199-235,317-361 | CaseSensitiveOptions is stored but never consulted` — with false: `HasOption v` on `-V` → false; `CheckOptions v verbose` → `Invalid option: -V`. Fix: lower-case both sides when false.

`TCA-07 | MED | :292-296 | GetOptionValues result "count:${values[*]}" is lossy and IFS-dependent` — `-f "a b" -f c` → `2:a b c`. Fix: out-array name + `RESULT=count` (R10).

`TCA-08 | MED | :363-380 | LongOpts array-vs-string interpretation is coupled to whether Opts/NonOpts were passed` — `CheckOptions "" lo o n` ok, `CheckOptions "" lo` → `Invalid option: --help`. `("${long_ref[@]:-}")` turns an empty array into one `""` option. Fix: decide by `declare -p`; use `"${long_ref[@]}"`.

`TCA-09 | MED | :387,436-439,445-448 | AllErrors parsed but ignored — loop breaks at first error`.

`TCA-10 | MED | :502-511 | No DoRun; Run is a fork-per-10 ms busy loop that cannot be stopped from a background job` — `grep -c DoRun` = 0 while docs describe it. Fix: `proc DoRun` (default: Terminate), `while [[ $Terminated != true ]]; do $this.call DoRun; done` reading the property nameref directly.

`TCA-11 | MED | :596-599 | Location returns the kklass directory` — `BASH_SOURCE[0]` inside an eval'd body is kklass.sh. Fix: `kk.getScriptDir "$0"`.

`TCA-12 | LOW | :497-499 | Terminate exports EXITCODE into the environment of every child process`.
`TCA-13 | LOW | :432,441,120-124 | '-' and non-leading '--' become non-options; leading '--' is silently dropped by SetArgs`.
`TCA-14 | LOW | :481,459-465 | GetNonOptions leaves a global _dummy_opts array; out-arrays named like internal locals silently receive nothing`.
`TCA-15 | LOW | :541-562 | GetEnvironmentList: env|sort fork, values containing newlines split into bogus entries`.
`TCA-16 | LOW | :564-584 | Log: format args ignored, filter is a substring match, output on stdout`.
`TCA-17 | LOW | :199-235,181-197 | First occurrence wins; FPC 3.2.2 FindOptionIndex scans downward (last wins); value check hardcodes '-'` (R10: last wins).
`TCA-18 | LOW | :341,352 | Error text "Invalid option: -x" vs FPC 'Invalid option at position %d: "%s"'`.
`TCA-19 | LOW | :7,85-86,115-118 | Dead code: unset of non-existent _call_silent; _CachedShortOpts/_CachedGetoptOpts written, never read`.
`TCA-20 | LOW | :518-521 | OnException with spaces → "command not found", then Terminate still runs` — validate with `declare -F`.

Reserved-name check: no member collides with kklass reserved names; `state` is used only as the framework nameref. `a.delete` leaves no `a_*` variables.

### Test gaps
- tstringhelper 037 (split) asserts `*a*` only; 027:64,73 and 034:28,55,64 accept either of two answers; 041 only `true`/`false`; 047/050 ASCII only; no locale pinned; no non-ASCII before the searched char.
- No tests for: negative/non-numeric indices, values starting with `-n`/`-e`, direct (non-`$()`) calls, replace default flags vs FPC, quotedString custom-quote doubling, newline inputs to split/quotedString, perf ≥10 KB.
- tcustomapplication 004/016 (`Run &` + `kill`) pass on both branches; 003/007/010/014 assert only `$? -eq 0`; 008:90/011 guarded by `ParamCount>0`; 027:96-101 passes either way; 013 AllErrors with one bad option; 022 never sets `CaseSensitiveOptions=false` before parsing; 019 writes helper apps to `/tmp` and guesses the repo path from cwd.
- No tests for: `--opt=value` value extraction, `:`/`::` consumption and "needs an argument" errors, `-`/`--` mid-argv, Location correctness, EnvironmentVariable with bad names, GetOptionValues with spaces, fresh-instance `_EnsureArgsInitialized`.
- Docs drift: TCustomApplication.md :218/271/345/407/417/803 and :179/:601/:828 (DoRun); TStringHelper.md :1299 (quote doubling), :1824 (control chars), 0-based *character* indexing.
