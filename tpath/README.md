# kcl/tpath — TPath for bash

A bash port of Free Pascal's `TPath` / .NET `System.IO.Path` as a kklass
**static** class: pure path-string arithmetic (plus one filesystem member,
`getAttributes`), no per-instance state, every member reached as
`tpath.<member>`.

```bash
source kcl/tpath/tpath.sh

tpath.combine /c/tmp file.txt      # RESULT=/c/tmp/file.txt (direct: prints nothing)
tpath.getFileName "$RESULT"        # RESULT=file.txt
name="$(tpath.getFileName 'C:\Users\me\f.txt')"   # f.txt — $( ) still works
if tpath.isPathRooted "$p"; then ... fi           # predicates answer with rc
tpath.getDirectoryName /home/user/ # RESULT=/home/user   (FPC ExtractFileDir)
tpath.getFullPath nosuch/rel/x     # RESULT=$PWD/nosuch/rel/x
```

It is the shared foundation of [`tfile`](../tfile/README.md) and
[`tdirectory`](../tdirectory/README.md): both source it, both answer through
its return helper, and the timestamp/attribute helpers they need live here so
the code exists exactly once.

## Contract

This unit follows the [kcl contract](../README.md#1-the-kcl-contract):

- **Values come back in `RESULT`.** A direct call prints nothing; `$(tpath.x)`
  prints the value exactly once but forks. Values are data — `-e`, `-n`,
  embedded newlines and backslashes round-trip.
- **Predicates answer with `rc`** (default R8) *and* leave `true`/`false` in
  `RESULT`, so both `if tpath.isPathRooted "$p"` and the older
  `[[ "$(tpath.isPathRooted "$p")" == true ]]` are correct. Under `set -e` call
  a predicate from an `if`, a `&&`/`||` or a `!`.
- **Errors are `rc 1` + `RESULT=''`** and print nothing. Only `getAttributes`
  can fail; every parsing member answers for every input, empty included.
- **`set -eu` clean**, loadable and re-loadable.
- **No forks** except `realpath` in `getFullPath`, `stat` in `getAttributes`
  and `mktemp`/`uuidgen` in the temp-name members — external tools, once per
  call. `uname` runs once at load, not per call.
- **UTF-8**: the unit exports `LC_CTYPE=C.UTF-8` when `LC_ALL`, `LC_CTYPE` and
  `LANG` are all empty.

### Members are `static proc`, not `static func`

kklass's *thin* static dispatcher — the one a class without static variables
receives — re-prints `kk._return`'s value **unconditionally**, i.e. on a direct
call too. A `static func` would therefore echo on every call, which is exactly
what decision D3 set out to remove. The members are `static proc` and return
through `tpath._ret`, which is `kk._return`'s contract with the subshell test
kept and the dispatcher's printf avoided. `tregex.sh` records the same
measurement in its header.

## Separators (decision D5)

On MSYS/cygwin the shell, every external tool and every path a caller types use
`/`, so:

| | value |
|---|---|
| `getDirectorySeparatorChar` | `/` on **every** platform |
| `getAltDirectorySeparatorChar` | `\` on Windows, `/` elsewhere — the separator still **accepted on input** |
| `getPathSeparator` | `;` on Windows, `:` elsewhere (this names the `PATH` list separator, not a directory separator) |
| `getVolumeSeparatorChar` | `:` on Windows, `/` elsewhere |
| `getExtensionSeparatorChar` | `.` |

Every parser accepts **both** separators on input, so `C:\Users\me\f.txt`,
`/a/b\c.txt` and `\\srv\share\f.txt` all split correctly, and the output of
`combine` can be parsed back by `getFileName`/`getDirectoryName` — which it
could not before (findings G6-01/G6-15).

A note for anyone editing the parsers: a bracket expression **cannot** carry a
backslash. `${p##*[/\\]}` and `[[ $p == [/\\]* ]]` match neither `/` nor `\` on
bash 5.2/5.3 — that is the mechanism behind G6-01. Use `"$__TPATH_BS"`
(`${p##*"$__TPATH_BS"}`, `[[ $p == *"$__TPATH_BS"* ]]`).

## API

| Member | Result | Notes |
|---|---|---|
| `getDirectorySeparatorChar` / `getAltDirectorySeparatorChar` / `getPathSeparator` / `getVolumeSeparatorChar` / `getExtensionSeparatorChar` | the constant | see the table above |
| `combine a b` | joined path | `b` rooted → `b`; all trailing separators of `a` stripped; joint is `/` |
| `getFileName p` | after the last `/` or `\` | FPC `ExtractFileName`; `""` when `p` ends in a separator |
| `getDirectoryName p` | the directory part | FPC `ExtractFileDir` / .NET `GetDirectoryName`: trailing separators stripped, cut at the last separator of either kind, **root kept** (`/file.txt` → `/`, `C:\f.txt` → `C:\`), `""` when there is no directory part |
| `getExtension p` | `.ext` or `""` | of the FILE NAME only; `.bashrc` → `.bashrc` (FPC `ExtractFileExt`) |
| `getFileNameWithoutExtension p` | name minus extension | |
| `changeExtension p ext` | rewritten path | FPC `ChangeFileExt`: the scan stops at a directory or drive separator, so a dotted DIRECTORY is never touched. A leading `.` is added if missing (.NET behaviour); an empty `ext` drops the extension |
| `hasExtension p` | rc + `true`/`false` | of the file name |
| `getPathRoot p` | root, input characters preserved | FPC `ExtractFileDrive` + the POSIX root: `//server/share`, `C:`, `/`, or `""` |
| `isPathRooted p` / `isRelativePath p` | rc + `true`/`false` | rooted = leading separator or `X:` |
| `getFullPath p` | absolute, normalised | `realpath -m` — components need **not** exist |
| `isUNCPath p` / `isUNCRooted p` | rc + `true`/`false` | two leading separators of either kind |
| `isDriveRooted p` | rc + `true`/`false` | `X:` prefix |
| `isExtendedPrefixed p` | rc + `true`/`false` | `//?/…` |
| `driveExists p` | rc + `true`/`false` | Windows only, and it asks the filesystem (`/c` for `C:`), not just the syntax |
| `getTempPath` / `getHomePath` / `getDocumentsPath` / `getDownloadsPath` | a path | `TMPDIR`/`TEMP`/`TMP`/`/tmp`; `$HOME` |
| `getTempFileName` | a NEW empty temp file | `mktemp`; the caller owns (and removes) it |
| `getGUIDFileName [withDashes]` / `getRandomFileName` | a name | `uuidgen` when available |
| `isValidFileNameChar c` / `isValidPathChar c` | rc + `true`/`false` | one character; the Windows-invalid set (`/ \ : * ? " < > |` + control). `~` is **valid** |
| `hasValidFileNameChars s [allowWildcards]` / `hasValidPathChars s [allowWildcards]` | rc + `true`/`false` | separators and the drive colon are legal in a PATH |
| `matchesPattern name pattern [caseSensitive]` | rc + `true`/`false` | bash glob; the caller's `nocasematch` is saved and restored |
| `getAttributes p [followLink]` | FPC token list | `faDirectory`/`faNormal` + `,faReadOnly` + `,faHidden` + `,faSystem`; `followLink=false` describes the LINK. rc 1 for a missing path |

Per-member upstream reference (and the map of what is *not* ported):
[docs/TPath.md](docs/TPath.md).

## Divergences from FPC/.NET (all tested)

| Topic | upstream | here |
|---|---|---|
| `DirectorySeparatorChar` on Windows | `\` | `/` (decision D5); `\` is the ALT separator and is accepted on input |
| `changeExtension p ""` | .NET keeps the dot (`file.`) | drops the extension (`file`) — pinned by test 002 |
| `changeExtension p "md"` | FPC appends verbatim (`filemd`) | adds the dot (.NET `ChangeExtension`) |
| `getPathRoot 'C:\x'` | .NET `C:\` | `C:` (FPC `ExtractFileDrive`) |
| attribute set | full Windows attribute word | the five tokens above, derived from the POSIX mode |
| `getAttributes` read-only | the FILE_ATTRIBUTE_READONLY bit | the owner write bit of the mode — so the FollowLink answers can differ |

`chmod` on a **directory** is a no-op on MSYS/NTFS (measured: `chmod a-w d`
returns 0 and the mode stays `755`), so a directory can never report
`faReadOnly` here, while a file can.

## Tests

`bash kcl/tpath/tests/tests.sh` — 243 cases on bash 5.2.37 and 5.3.9.
`016_Contract.sh` holds the kcl contract (`set -eu`, the return contract, the
locale self-heal, the failing member under `set -e`); `017`–`020` hold the
2026-09-06 review regressions: separators and UNC roots (G6-01/15/22), the
parsers (G6-02/12/13), the platform members (G6-14/16/20/21) and the D3/R8
return contract.
