# kcl/tfile — TFile for bash

A bash port of Free Pascal's `TFile` / .NET `System.IO.File` as a kklass
**static** class: no per-instance state, every member reached as
`tfile.<member>`.

```bash
source kcl/tfile/tfile.sh

tfile.create      /tmp/a.txt
tfile.appendAllText /tmp/a.txt "hello"     # writes DATA — "-n" is two bytes
tfile.readAllText /tmp/a.txt               # RESULT="hello" (direct: prints nothing)
text="$(tfile.readAllText /tmp/a.txt)"     # still works, but $( ) forks
tfile.readAllTextVar /tmp/a.txt buf        # fork-free, trailing newlines kept
if tfile.exists /tmp/a.txt; then ... fi    # predicates answer with rc
tfile.setLastWriteTimeUtc /tmp/a.txt "2024-01-01 12:00:00"
tfile.delete /tmp/a.txt
```

The unit sources [`tpath`](../tpath/README.md), which carries the path parsers
(both separators, decision D5), the return helper and the shared timestamp and
attribute helpers it uses together with
[`tdirectory`](../tdirectory/README.md).

## Contract

This unit follows the [kcl contract](../README.md#1-the-kcl-contract):

- **Values come back in `RESULT`.** A direct call prints nothing; `$(tfile.x)`
  prints the value exactly once but forks.
- **Predicates answer with `rc`** (default R8) *and* leave `true`/`false` in
  `RESULT` — `tfile.exists` is the only one. Under `set -e` call it from an
  `if`, a `&&`/`||` or a `!`.
- **Errors are `rc 1` + `RESULT=''`** and print nothing; a bad
  output-variable name is **`rc 2`**.
- **`set -eu` clean**, loadable and re-loadable.
- **Numeric arguments are validated** before they reach `(( ))`:
  `tfile.integerToFileAttributes 'x[$(touch pwn)]'` is rc 1, not a command.
- **`--` before every user path**, so `tfile.delete -f` removes the file named
  `-f` and `tfile.readAllText -` reads the file named `-`, not stdin.
- **No forks** on the reading path (`read -d ''`, not `$(cat)`); `cp`, `mv`,
  `stat`, `touch`, `chmod`, `openssl`, `readlink` and `ln` are external tools,
  once per call.
- **UTF-8**: the unit exports `LC_CTYPE=C.UTF-8` when `LC_ALL`, `LC_CTYPE` and
  `LANG` are all empty.

Members are `static proc` rather than `static func` for the reason documented
in [tpath's README](../tpath/README.md#members-are-static-proc-not-static-func).

## Reading a file byte-faithfully

`$( )` strips **every** trailing newline — that is bash, not this unit. Three
shapes, in order of fidelity:

```bash
tfile.readAllTextVar "$f" buf   # buf holds every byte; RESULT = character count
tfile.readAllText   "$f"        # RESULT holds every byte
text="$(tfile.readAllText "$f")"  # convenient, forks, trailing newlines gone
```

A **NUL** byte cannot live in a bash variable, so a read stops at the first one
and `writeAllBytes` writes the string it was given, not arbitrary bytes. For
real binary data use `cp`/`dd` directly; this is a documented limit of the
port, not a bug to file.

`readAllLines FILE ARRAY` fills a caller array (one entry per line) and puts
the line COUNT in `RESULT` — the newline-safe form. Call it **directly**;
`$( )` runs it in a subshell and throws the fill away. The array name is
validated (kcl/README.md §1.7): a reserved or malformed name is rc 2 and
nothing is written.

## API

| Member | Result | Notes |
|---|---|---|
| `create f` / `createText f` | — / `f` | truncates or creates |
| `appendAllText f text` | — | `printf '%s'`: `-n`, `-e`, `-neE` are data |
| `appendText f` | `f` | opens for append (returns the handle = the name) |
| `writeAllBytes f data` | — | the string, not arbitrary bytes (see above) |
| `exists f [followLink]` | rc + `true`/`false` | `followLink=false` also accepts a broken link |
| `delete f` | — | on a symlink removes the LINK |
| `copy src dst [overwrite]` | — | `overwrite=false` (default) + existing `dst` → rc 1 |
| `move src dst` | — | existing `dst` → rc 1 |
| `replace src dst [backup]` | — | .NET `File.Replace`: `dst` is replaced by `src`, the old `dst` becomes `backup`, and **`src` is consumed** |
| `encrypt f [pw]` / `decrypt f [pw]` | — | `openssl enc -aes-256-cbc -pbkdf2`; the temp file is unpredictable and lands **next to** `f` |
| `fileAttributesToInteger '[fa…]'` / `integerToFileAttributes n` | the number / `[Token, …]` | `n` goes through `kk.isInt` |
| `getAttributes f [followLink]` | FPC token list | delegates to `tpath.getAttributes`; `followLink=false` describes the LINK |
| `setAttributes f '[fa…]'` | — | `faReadOnly` → `chmod a-w`, anything else → `chmod u+w` |
| `getCreationTime[Utc] f` | `YYYY-MM-DD HH:MM:SS` | `stat %W`, falling back to `%Y` when the filesystem has no birth time |
| `getLastAccessTime[Utc] f` / `getLastWriteTime[Utc] f` | same | `%X` / `%Y` |
| `setLastAccessTime[Utc] f v` / `setLastWriteTime[Utc] f v` | — | `v` = epoch seconds or a date string; the `Utc` form reads a STRING as UTC. Implemented with `touch -d @epoch`, so a value round-trips exactly |
| `setCreationTime[Utc] f v` | — | **rc 1** — a creation time cannot be set here, exactly as .NET's `File.SetCreationTime` on Unix |
| `createSymLink link target` | rc + `true`/`false` | needs a native symlink (Developer Mode or an elevated shell); a missing target, a missing link directory or an **occupied** link path is `false` + rc 1 (an existing path is never overwritten and never removed) |
| `getSymLinkTarget link` | the stored target | rc 1 for a non-link; a BROKEN link still answers |
| `open f mode` / `openRead f` / `openText f` / `openWrite f` | `f` | a "handle" is the file name; `mode` ∈ `fmOpenRead`, `fmOpenWrite`, `fmOpenReadWrite` |
| `readAllText f` / `readAllBytes f` | the content | fork-free, byte-faithful up to the first NUL |
| `readAllTextVar f NAME` | character count in `RESULT` | fills `NAME`; bad name → rc 2 |
| `readAllLines f [ARRAY]` | the text, or the line count | with `ARRAY`: fills it, RESULT = count, bad name → rc 2 |

Per-member upstream reference (and the map of what is *not* ported):
[docs/TFile.md](docs/TFile.md), [docs/TFileAttribute.md](docs/TFileAttribute.md).

## Divergences from FPC/.NET (all tested)

| Topic | upstream | here |
|---|---|---|
| `SetCreationTime` | sets the creation time on Windows | rc 1 (no POSIX API, and Windows' is not reachable through `touch`) — .NET throws on Unix |
| stream handles | `TFileStream` objects | the file NAME is the handle; `open*` only validates |
| `TEncoding` parameter | selects an encoding | not ported: a trailing argument to `readAllText` is ignored, and the second argument of `readAllLines` is the OUTPUT ARRAY |
| `writeAllBytes` | arbitrary bytes | the string given (bash variables cannot hold NUL) |
| attribute set | full Windows attribute word | the five FPC tokens `tpath.getAttributes` derives from the POSIX mode |
| symlinks | always available | need a native link: MSYS/cygwin `ln -s` is in COPY mode by default, and `cmd mklink` fails without privilege even with Windows paths |

## Tests

`bash kcl/tfile/tests/tests.sh` — 250 cases on bash 5.2.37 and 5.3.9.
`039_Contract.sh` holds the kcl contract (`set -eu`, injection, `--` before
paths, the return contract, the locale self-heal); `040`–`043` hold the
2026-09-06 review regressions: real symlinks (G6-05, replacing 12 tests that
used to "pass as skipped"), the timestamp and attribute setters (G6-07/08/26),
the byte-faithful reads and `replace` (G6-18/19), and the D3/R8 return
contract. `tests/symlink_helper.sh` is the shared probe that asks for a NATIVE
symlink and verifies it with `[[ -L ]]`.
