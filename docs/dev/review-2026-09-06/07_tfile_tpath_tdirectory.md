# Reviewer report G6 — tfile / tpath / tdirectory (2026-09-06)

Repro scripts: `repro/g6/probe_{tfile,tpath,tpath2,bs,tdir}.sh` (all leave no files behind).

### Summary
Three old, non-ledger units; suites green on both bashes: tfile 120/120, tpath 112/112, tdirectory 197/197 — but the suites are weak (12 symlink tests always "pass as skipped" on MSYS, all setter tests assert only exit status/non-empty, tpath 003 encodes non-parity expectations). tdirectory is the soundest (glob-based, no forks in listing loops); tpath is the weakest — on Windows `getFileName/getExtension/getPathRoot` never split on `\`, so `tpath.combine` output cannot be parsed back by tpath itself, and `changeExtension` rewrites the *directory* part when a directory name contains a dot; tfile has silent no-op setters and a data-swallowing `appendAllText`.

### Findings

`G6-01 | HIGH | tpath.sh:163,200,219,288 | Backslash is not recognised as a separator by getFileName/getExtension/getFileNameWithoutExtension/hasExtension/getPathRoot`
Pattern `${path##*[$SEP$ALT]}` expands to `[\/]`; inside a bracket expression `\` escapes `/`, so the class is `/` only. `tpath.getFileName 'C:\Users\me\f.txt'` → unchanged (expected `f.txt`); `getExtension 'C:\dir.d\file'` → `.d\file`; `getPathRoot '\\srv\share\f.txt'` → `//srv\share\f.txt`. Round trip: `c=$(tpath.combine /c/tmp file.txt)` → `/c/tmp\file.txt`; `getFileName "$c"` → `tmp\file.txt`. Reliable fix: two-step strip `f="${path##*/}"; f="${f##*\\}"`. (Decision D5.)

`G6-02 | HIGH | tpath.sh:239-244 | changeExtension operates on the whole path, not the file name`
`base_path="${path%.*}"`. `tpath.changeExtension /home/u/.config/app/file .bak` → `/home/u/.bak`; `./file .txt` → `.txt`; `../file .txt` → `..txt`; `dir.d/file .txt` → `dir.txt`; `C:\dir.d\file .txt` → `C:\dir.txt`. Fix: split dir/name first, apply `%.*` to the name only, rejoin.

`G6-03 | HIGH | tfile.sh:91 | appendAllText silently drops text that looks like echo options`
`tfile.appendAllText a.txt "-n"`, `"-e"`, `"-neE"` append nothing (size stays 0, rc 0). Fix: `printf '%s' "$text" >> "$file"`.

`G6-04 | HIGH | tdirectory.sh:95 | delete on a dir symlink with trailing slash deletes the TARGET's contents and keeps the link`
Reproduced with `MSYS=winsymlinks:native ln -s tgt lnk`: `tdirectory.delete "lnk/"` → rc 0, `tgt/keep` gone, `lnk` still present; `tdirectory.delete lnk` correctly removes only the link. Fix: strip trailing separators; if `[[ -L $dir_path ]]`, `rm "$dir_path"` only. (R13.)

`G6-05 | HIGH | tfile.sh:120-131 | createSymLink never works on MSYS: cmd /c mklink is given POSIX paths`
`tfile.createSymLink "$W/lnk.txt" "$W/tgt.txt"` → `false`, rc 1, nothing created; with `cygpath -w` paths it succeeds without admin on this box. Tests 005/010/012/019 never see it because their probe `ln -s <nonexistent>` fails under MSYS copy-mode, so all 12 symlink tests report `PASS (skipped)`. Fix: `$(cygpath -w …)` to mklink (or `MSYS=winsymlinks:native ln -s`); make the test probe use an existing target.

`G6-06 | MED | tfile.sh:219,224-228 | integerToFileAttributes evaluates its argument arithmetically → command injection` — `tfile.integerToFileAttributes 'x[$(touch pwned)]'` creates `pwned`.

`G6-07 | MED | tfile.sh:267-273,195 | set*Time / setAttributes are silent no-ops; getAttributes always "faNormal"`
`tfile.setLastWriteTime f "2020-06-15 12:00:00"` → rc 0, mtime unchanged; `tfile.setAttributes f "[faReadOnly]"` → rc 0, still writable; `chmod 444 f; tfile.getAttributes f` → `faNormal` (tpath.getAttributes returns `faNormal,faReadOnly`). tdirectory implements these for real. Fix: reuse tdirectory's `_touch_time`/`chmod` logic; delegate getAttributes to tpath (R13).

`G6-08 | MED | tdirectory.sh:489-500 | *Utc setters store a time shifted by the local TZ offset`
`date -u -d … +%Y%m%d%H%M.%S` then `touch -t` (LOCAL): on +0300 `setLastWriteTimeUtc d "2024-01-01 12:00:00"; getLastWriteTimeUtc d` → `09:00:00`. Also `setCreationTime` maps to `-m`. Fix: epoch + `touch -d "@$epoch"`.

`G6-09 | MED | tdirectory.sh:233,255,278,321,365,409 | Listings never return dot-entries; isEmpty disagrees` — no `dotglob`; `isEmpty` uses `ls -A`. (R13: include, FPC/.NET parity.)

`G6-10 | MED | tdirectory.sh:132,164 | copy/move into an existing destination nests the source inside it` — `tdirectory.copy src dst` → `dst/src/a.txt`. Fix: `cp -r "$src/." "$dst"`; move: `[[ -e $dst ]] && return 1`.

`G6-11 | MED | tfile.sh:104-106,255-257; tdirectory.sh:95,200 | No `--` before user paths` — `tfile.delete -f` → rc 0, file kept; `tfile.readAllText -` reads stdin; `tdirectory.delete -rf` → rc 0, dir kept; `setCurrentDirectory -` → `$OLDPWD`.

`G6-12 | MED | tpath.sh:176-189 | getDirectoryName: root and trailing-separator handling not parity; mixed separators wrong`
`/file.txt` → `` (expected `/`); `C:\file.txt` → `C:`; `/home/user/` → `/home` (ExtractFileDir: `/home/user`); `/home/user//` → `/home/user`; `C:/Users/me\f.txt` → `C:/Users`. Test 003 asserts the wrong results. Fix: strip all trailing seps, cut at the LAST of either separator, keep the root when the remainder is empty.

`G6-13 | MED | tpath.sh:347-348 | getFullPath returns the raw relative input when an intermediate component is missing; `-e` returns empty` — Fix: `realpath -m -- "$path"`.

`G6-14 | MED | tpath.sh:668-669 | getAttributes FollowLink flag is inverted` (`stat -L` added when `follow_link == "false"`). SUSPECTED from code.

`G6-15 | MED | tpath.sh:139-153 (design) | combine emits `\` on MSYS, producing mixed-separator paths` — `tpath.combine /c/projects/kkbot/kbool kcl` → `/c/projects/kkbot/kbool\kcl`; test 001 expects `/home/user\documents/file.txt`. (D5.)

`G6-16 | MED | tpath.sh:330,265,219,422,460,477; tdirectory.sh:98,141,205; tfile.sh:120 | Avoidable forks in cheap methods`
200 calls on 5.2: `tpath.combine` direct 0.65 ms vs `$(…)` 23 ms; `isRelativePath` 21 ms (inner `$(tpath.isPathRooted)`); `driveExists` 45 ms (`$(uname -s)` per call); `tdirectory.isEmpty` 73 ms (`$(ls -A)`). Fix: test the readonly platform constants; call sibling bodies directly; isEmpty via a glob loop.

`G6-17 | MED | tdirectory.sh:239,262,286 | Recursive listing follows directory symlinks → cycles` — with `loop/a/back -> loop`, `getDirectories loop '*' AllDirectories` returned 21 entries for 1 real subdirectory. Fix: `[[ -L $path ]] && continue` (R13).

`G6-18 | LOW | tfile.sh:255-257,274 | readAllText/readAllBytes/writeAllBytes have no byte fidelity` — `$()` strips trailing newlines; NUL dropped; `writeAllBytes f $'x\0y'` writes 1 byte. (R13: `readAllTextVar`.)
`G6-19 | LOW | tfile.sh:258-266 | replace keeps the source file`.
`G6-20 | LOW | tpath.sh:559,595-600,616-621,424 | Windows-invalid characters accepted; `~` rejected; driveExists checks syntax only`.
`G6-21 | LOW | tpath.sh:649 | matchesPattern clears the caller's nocasematch`.
`G6-22 | LOW | tpath.sh:149-150,286-289 | combine strips only one trailing separator; getPathRoot UNC returns only `//server``.
`G6-23 | LOW | tfile.sh:182; tdirectory.sh:209 | Globals leaked: `attr_parts`, `letter``.
`G6-24 | LOW | tdirectory.sh:108-115,365 | exists ignores FollowLink; echo -n inconsistency; trailing slash doubled in listings`.
`G6-25 | LOW | tdirectory.sh:233 etc. | `failglob` set by caller breaks listings`.
`G6-26 | LOW | tfile.sh:159-160,210 | _crypt_file temp dir detection only understands `/`; getCreationTime lacks the `-1` fallback tdirectory has`.
`G6-27 | LOW | tdirectory.sh:1-8 | No re-source guard (tfile/tpath have one)`.

### Test gaps
- 12 symlink tests (tfile 005 ×4, 010 ×3, 012 ×2, 019 ×3) always `PASS (skipped)` on MSYS; `createSymLink` is actually broken.
- tfile 030-036 (setters) assert only `rc==0`; tdirectory 027-029 assert only a non-empty getter.
- tpath 009 `getFullPath` cases assert only non-empty; tpath 001 "Performance" has a 20 s threshold; tdirectory 012 "returns result" is `-n || -z` (tautology).
- tpath 003 and 001/007 encode non-parity expectations.
- No coverage for: backslash inputs, dotted directory names in changeExtension, hidden entries, existing destination in copy/move, leading-dash names, `-`, names with `*?[]`/newline, text starting with `-n`/`-e`, trailing-newline round trip, symlink dirs in delete/recursion, UTC setter values.
- tpath 012 writes fixed names into the real `%TEMP%` (not `_KT_TMPDIR`) and cleans only on the happy path.
- tdirectory 013/014 expect `en_US.UTF-8` collation order; brittle.
- tdirectory 001 prints `DEBUG:` lines to stderr; tfile 027/028 reassign `_KT_TMPDIR` and use it unquoted.
