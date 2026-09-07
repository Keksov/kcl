# kcl/tdirectory — TDirectory for bash

A bash port of Free Pascal's `TDirectory` / .NET `System.IO.Directory` as a
kklass **static** class: no per-instance state, every member reached as
`tdirectory.<member>`.

```bash
source kcl/tdirectory/tdirectory.sh

tdirectory.createDirectory /tmp/work/sub
tdirectory.getFiles /tmp/work                 # RESULT = newline-joined paths
declare -a files
tdirectory.getFiles /tmp/work '*.txt' AllDirectories files   # RESULT = count
if tdirectory.isEmpty /tmp/work; then ... fi  # predicates answer with rc
tdirectory.copy /tmp/work /tmp/backup         # existing dest -> CONTENTS merge
tdirectory.setLastWriteTimeUtc /tmp/work "2024-01-01 12:00:00"
tdirectory.delete /tmp/work                   # on a symlink: only the link
```

The unit sources [`tpath`](../tpath/README.md), which carries the path parsers
(both separators, decision D5), the return helper and the shared timestamp and
attribute helpers it uses together with [`tfile`](../tfile/README.md).

## Contract

This unit follows the [kcl contract](../README.md#1-the-kcl-contract):

- **Values come back in `RESULT`.** A direct call prints nothing;
  `$(tdirectory.x)` prints the value exactly once but forks.
- **Predicates answer with `rc`** (default R8) *and* leave `true`/`false` in
  `RESULT`: `exists`, `isEmpty`, `isRelativePath`. Under `set -e` call them
  from an `if`, a `&&`/`||` or a `!`.
- **Errors are `rc 1` + `RESULT=''`** and print **nothing** — the old bodies
  wrote `Error: …` to stderr on every miss; a diagnostic now appears only under
  `VERBOSE_KKLASS=debug`. A bad output-array name is **`rc 2`**.
- **`set -eu` clean**, loadable and re-loadable.
- **`--` before every user path**, and `setCurrentDirectory -` means the
  DIRECTORY named `-` (bash's `cd` reads a lone `-` as `$OLDPWD` even after
  `--`, so the member spells it `./-`).
- **No forks**: the listings and `isEmpty` are glob loops, `getLogicalDrives`
  reads a load-time constant. `cp`, `mv`, `rm`, `rmdir`, `mkdir`, `stat`,
  `touch` and `chmod` are external tools, once per call.
- **UTF-8**: the unit exports `LC_CTYPE=C.UTF-8` when `LC_ALL`, `LC_CTYPE` and
  `LANG` are all empty.

Members are `static proc` rather than `static func` for the reason documented
in [tpath's README](../tpath/README.md#members-are-static-proc-not-static-func).

`setCurrentDirectory` really does `cd` in the **caller's** shell: the thin
static dispatcher does not run the body in a subshell.

## Listings

```
getFiles DIR [PATTERN] [TopDirectoryOnly|AllDirectories] [OUTARRAY]
getDirectories  … same shape
getFileSystemEntries … same shape
```

* **Dot-entries are included** (FPC/.NET parity, default R13) — and `isEmpty`
  and the non-recursive `delete` agree with them.
* **Recursion does not descend into a directory symlink**, so a link that
  points back up its own tree cannot produce a cycle.
* **`OUTARRAY` is the newline-safe form**: the array is filled one entry per
  element and `RESULT` is the COUNT. Without it the entries come back
  newline-joined in `RESULT`, which is ambiguous for a name that contains a
  newline. Call the array form **directly** — `$( )` throws the fill away. The
  name is validated (kcl/README.md §1.7): reserved or malformed → rc 2.
* Ordering is the shell's glob order in the **ambient** locale (the test
  runners pin `LC_ALL=C.UTF-8`, i.e. codepoint order). The unit no longer
  forces `LC_COLLATE=en_US.UTF-8` behind the caller's back.
* A caller's `failglob` cannot break a listing, and `dotglob`/`failglob`/
  `extglob` are restored exactly as they were found.

## API

| Member | Result | Notes |
|---|---|---|
| `createDirectory d` | — | `mkdir -p`; an existing directory is not an error |
| `delete d [recursive]` | — | trailing separators stripped; a SYMLINK loses only the link; `recursive=false` needs the directory to be empty (dot-entries count); a path that is nothing but separators is refused |
| `exists d [followLink]` | rc + `true`/`false` | `followLink=false` does not accept a symlink |
| `isEmpty d` | rc + `true`/`false` | dot-entries count; a missing path is `false` |
| `copy src dst` | — | existing `dst` receives the **contents** (dot-entries included); `dst` an existing FILE → rc 1 |
| `move src dst` | — | existing `dst` → **rc 1**, source untouched |
| `isRelativePath p` / `getDirectoryRoot p` / `getParent p` | rc+bool / root / directory | `tpath` semantics; `getParent .` uses `$PWD` |
| `getCurrentDirectory` / `setCurrentDirectory d` | `$PWD` | the `cd` happens in the caller's shell |
| `getLogicalDrives` | `C: D: …` / `/` | the mounted MSYS drive mounts; no `uname` fork |
| `getFiles` / `getDirectories` / `getFileSystemEntries` | see **Listings** | |
| `getAttributes p [followLink]` | FPC token list | delegates to `tpath.getAttributes` |
| `setAttributes p '[fa…]'` | — | `faReadOnly` → `chmod a-w`, anything else → `chmod u+w` |
| `getCreationTime[Utc] d` | `YYYY-MM-DD HH:MM:SS` | `stat %W`, falling back to `%Y` |
| `getLastAccessTime[Utc] d` / `getLastWriteTime[Utc] d` | same | `%X` / `%Y` |
| `setLastAccessTime[Utc] d v` / `setLastWriteTime[Utc] d v` | — | `v` = epoch seconds or a date string; the `Utc` form reads a STRING as UTC. `touch -d @epoch`, so a value round-trips exactly |
| `setCreationTime[Utc] d v` | — | **rc 1** — not settable here (the old body silently set the WRITE time) |

Per-member upstream reference (and the map of what is *not* ported):
[docs/TDirectory.md](docs/TDirectory.md).

## Divergences from FPC/.NET (all tested)

| Topic | upstream | here |
|---|---|---|
| `SetCreationTime` | sets the creation time on Windows | rc 1 (no POSIX API; .NET throws on Unix) |
| `Copy` into an existing directory | .NET throws `IOException` | merges the CONTENTS (default R13) |
| `Move` into an existing directory | .NET throws | rc 1, source untouched |
| listing result | `TStringDynArray` | newline-joined `RESULT`, or a caller array via `OUTARRAY` |
| `SearchOption` | enum | the strings `TopDirectoryOnly` (default) and anything else = `AllDirectories` |
| recursion into directory links | follows | does not (default R13) |
| directory `faReadOnly` | a real attribute | unreachable: `chmod` on a directory is a no-op on MSYS/NTFS (measured), so `setAttributes` answers rc 0 and the mode does not move |

## Tests

`bash kcl/tdirectory/tests/tests.sh` — 320 cases on bash 5.2.37 and 5.3.9.
`032_Contract.sh` holds the kcl contract (`set -eu`, the return contract, the
silent error path, the locale self-heal); `033`–`036` hold the 2026-09-06
review regressions: the listings (G6-09/17/24/25 and the output array), the
lifecycle (G6-04 symlink delete, G6-10 existing destination, G6-16 forks,
G6-24 FollowLink), the timestamps (G6-08 and R13) and the D3/R8 return
contract. `tests/symlink_helper.sh` is the shared probe that asks for a NATIVE
symlink and verifies it with `[[ -L ]]`.
