# Reviewer report T — tinifile (2026-09-06)

Repro scripts: `repro/g5/p1.sh … p3.sh`. FPC parity checked against current FPC `inifiles.pp`.

### Summary
`tinifile.sh` (985 lines) is a careful, fork-free port that matches the FPC reader/writer in most pinned rules; the suite is 84/84 on bash 5.2.37 and 5.3.9. No wrong result on the normal read path. The real problems are on the persistence/validation edges: (1) a `file_name` that is a directory makes `UpdateFile` "succeed" (rc 0, dirty cleared, nothing written, junk tmp left in the dir); (2) the PLAN 2.7 "refuse what FPC would corrupt" promise has two holes that turn keys into sections / drop keys on the next flush; (3) `SectionExists` diverges from FPC. Plus quadratic lookup/append cost (16 ms/append at 800 keys, 11 ms/read in the 20th section).

### Findings

`T1 | HIGH | tinifile.sh:345-373 | UpdateFile onto a directory path reports success, writes nothing, leaves junk`
`_updateNow` never checks `-d "$file_name"`. `mv -f tmp "$dir"` moves the tmp INTO the directory and returns 0, so `dirty=false` and rc 0 while no ini exists.
Repro: `mkdir d; TIniFile.new X d; X.WriteString a b c; echo rc=$? dirty=$(X.dirty); ls d` → `rc=0 dirty=false`, `d/d.tmp.<pid>` created. Expected rc 1 + memory/dirty kept.
Fix: at the top of the `-n "$file_name"` branch add `[[ -d "$file_name" ]] && { debug msg; return 1; }`; also `rm -f -- "$__tif_tmp"` on every failure branch.

`T2 | MED | tinifile.sh:396-409 (_validate), 241-247 | Ident starting with `[` + value ending with `]` is silently rewritten as a SECTION on flush`
Compose emits `[list=1,2]`; the normalization re-parse treats that as section `list=1,2`, the key vanishes and following keys migrate. FPC has the same hole, but the unit promises (README "Divergences", PLAN 2.7) to reject what FPC would corrupt.
Repro: `TMemIniFile.new F f.ini; F.WriteString s "[list" "1,2]"; F.UpdateFile; F.ReadString s "[list" DEF` → `DEF`; `F.SectionExists "list=1,2"` → rc 0.
Fix: in `_validate`, reject when `ident` starts with `[` and `value` ends with `]` (or reject idents starting with `[` outright).

`T3 | MED | tinifile.sh:243, 317-318 | A `[;name]` section in a file loses all its keys on the first UpdateFile`
Load stores section name `;name`; `_compose` treats any `;`-leading name as a comment-section and emits `;name` WITHOUT brackets; the re-parse turns it into a comment and the following keys become orphans (dropped).
Repro: `printf '[;x]\nk=v\n[y]\nz=1\n' > c.ini; TMemIniFile.new C c.ini; C.UpdateFile; cat c.ini` → `;x` / `k=v` / `[y]` / `z=1`; reopening lists only section `y`.
Fix: in `_fill` (S4 branch) treat `[;...]` as an invalid row or keep the brackets in `_compose` for names that came from a bracketed line.

`T4 | MED | tinifile.sh:563-570 | SectionExists returns true for empty / comment-only sections (FPC returns false)`
FPC: `SectionExists := Assigned(S) and not S.Empty`. `docs/TIniFile.md:45` claims "same".
Repro: `printf '[empty]\n[c]\n; only\n[full]\nk=1\n' > s.ini; TMemIniFile.new S s.ini; S.SectionExists empty; echo $?` → 0, FPC false; also `S.WriteString n k v; S.DeleteKey n k; S.SectionExists n` → 0, FPC false.
Fix: after `_findSection`, require one row with `kowner==slot` whose ident is non-comment.

`T5 | MED | tinifile.sh:733-764 | Eager DeleteKey/EraseSection swallow a failed flush (rc 0) while WriteString reports rc 1`
Repro: `touch blk; TIniFile.new E blk/x.ini; E.WriteString s k v` → rc 1; `E.DeleteKey s k; echo $?` → 0, `E.EraseSection s; echo $?` → 0. Fix: `TIniFile._maybeUpdate; return $?`.

`T6 | MED | tinifile.sh:155-174, 721-728 | Key lookup scans ALL rows of ALL sections and calls `_norm` per row → quadratic append, position-dependent reads`
Repro (cached, no flush): 200/400/800 appends → 3.96 / 8.34 / 16.4 ms per write (13.1 s total for 800); `ReadString sec1 k50` 3.4 ms vs `sec20 k50` 11.3 ms.
Fix: per-instance assoc index `${inst}_kidx["slot|normident"]=firstrow` (and `_sidx`), or at least precompute normalized idents once and store the next-free row index. (Decision R6: variant (a) first.)

`T7 | MED | tinifile.sh:368-372, 356 | Temp file leaked on failed replace; `mv`/`rm`/`mkdir` break on names starting with `-``
Repro: `cd d; TIniFile.new Y -x.ini; Y.WriteString a b c` → rc 1 and `-x.ini.tmp.<pid>` remains. The printf-failure branch (line 358) never removes a partially written tmp. Fix: `mv -f -- `, `rm -f -- `, `mkdir -p -- `; rm the tmp in the printf failure branch too.

`T8 | MED | tinifile.sh:356-368 | Read-only target is silently replaced and its permissions reset`
Repro: `printf '[s]\nk=1\n' > ro.ini; chmod 444 ro.ini; TIniFile.new R ro.ini; R.WriteString s k 2; echo $?; ls -l ro.ini` → rc 0, content `k=2`, mode `-rw-r--r--`. FPC's `SaveToFile` fails. Fix: `[[ -e "$file_name" && ! -w "$file_name" ]] → rc 1` before the tmp write.

`T9 | LOW | tinifile.sh:204-222 | ifoEscapeLineFeeds strips the backslash of the LAST line (FPC keeps it)`
Repro: `printf '%s\n' '[s]' 'k=a\' > e.ini; TIniFile.new E e.ini ifoEscapeLineFeeds; E.ReadString s k DEF` → `a`, FPC `a\`. Fix: after the loop, `(( __tif_have )) && __tif_fl+=( "${__tif_acc}\\" )`.

`T10 | LOW | tinifile.sh:380 | With ifoEscapeLineFeeds, writing a value ending in `\` (Windows paths!) merges the next key on flush`
Repro: `TMemIniFile.new W w.ini ifoEscapeLineFeeds; W.WriteString p dir 'C:\App\'; W.WriteString p name x; W.UpdateFile; W.ReadString p dir DEF` → `C:\Appname=x`; `name` → `DEF`. Fix: reject a value ending in `\` in `_validate` when ifoEscapeLineFeeds is set, or document.

`T11 | LOW | tinifile.sh:518-543 | StrToIntDef grammar gaps: leading blanks and bare `x`/`X` hex prefix rejected`
Values `" 5"` → 0 (FPC 5), `x1F` → 0 (FPC 31). Overflow wraps silently (`99999999999999999999` → 7766279631452241919, `$FFFFFFFFFFFFFFFFFFFF` → -1) — FPC returns Default.

`T12 | LOW | tinifile.sh:349-355 | Backslash-separated Windows paths never get the ForceDirectories treatment`
`${file_name%/*}` only splits on `/`; `C:\dir\x.ini` with a missing dir fails with a stderr message from `printf` and rc 1. Fix: normalize `\` → `/` for the dir computation.

`T13 | LOW | tinifile.sh:586,605,624,677,950 | Empty / instance-var-named out-array names produce kklass noise, rc 0`
`I.ReadSections ""` → `local: ': not a valid identifier`, rc 0; `dirty=(); I.ReadSections dirty` → nameref errors. Fix: `[[ "$2" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1`; document that instance-var names are reserved.

`T14 | LOW | tinifile_ledger.json:5-6, docs/TIniFile.md:45 | Ledger/docs drift` — ledger says `updated: 2026-07-12`, "UNCOMMITTED" although committed as kcl `fcde032`; docs claim SectionExists is "same" as FPC (T4).

### Test gaps
- No test for `file_name` being a directory, a read-only target, a `-`-leading name, or tmp cleanup after a failed flush (T1, T7, T8).
- No test for `SectionExists` on an empty or comment-only section, nor after `WriteString`+`DeleteKey` (T4).
- No test for duplicate-section `EraseSection` (first only; second still found — FPC parity, should be pinned).
- No test for the `[`-ident/`]`-value and `[;x]` round-trip corruptions (T2, T3).
- `ifoEscapeLineFeeds`: last-line trailing `\`, `\\`, and write-side values ending in `\` untested (T9, T10).
- `DeleteKey`/`EraseSection` rc on a failed eager flush untested (T5).
- `ReadInteger` overflow, leading-blank/`x`-prefix forms untested (T11); `ReadFloat` `1.`/`+.5`/`1e5` shapes untested.
- No test that `WriteString` with leading/trailing-space ident becomes unreachable after flush (`"k "` → `k`, FPC parity — worth pinning).
- Performance: nothing guards the quadratic append/lookup (relative assert: 800 appends < 10× 200 appends).
- `ReadSectionValues` with ONLY `svoIncludeQuotes` untested. Instance-name reuse without `delete` and `Rename ""`/`UpdateFile` with empty `file_name` untested.
