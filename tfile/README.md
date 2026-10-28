# kcl/tfile — TFile for bash

A bash port of Free Pascal's `TFile` / .NET `System.IO.File` as a kklass
**static** class: no per-instance state, every member reached as
`tfile.<member>`.

```bash
source /path/to/kbool/kbool.sh
kk.uses tfile

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
  `stat`, `touch`, `chmod`, `readlink` and `ln` are external tools, once per
  call; `encrypt`/`decrypt` start four `openssl` processes plus `tail`,
  `mktemp`, `mv` and (decrypt) `od` (see [Encryption](#encryption)).
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
| `encrypt f [pw]` / `decrypt f [pw]` | — | the KBTF1 format: AES-256-CBC + HMAC-SHA256 (encrypt-then-MAC), see [Encryption](#encryption); a wrong password or any changed byte is rc 1 with `f` untouched; `pw` defaults to `$TFILE_CRYPTO_PASSWORD`; the temp file is unpredictable and lands **next to** `f` |
| `fileAttributesToInteger '[fa…]'` / `integerToFileAttributes n` | the number / `[Token, …]` | `n` goes through `kk.isInt` |
| `getAttributes f [followLink]` | FPC token list | delegates to `tpath.getAttributes`; `followLink=false` describes the LINK |
| `setAttributes f '[fa…]'` | — | `faReadOnly` → `chmod a-w`, anything else → `chmod u+w` |
| `getCreationTime[Utc] f` | `YYYY-MM-DD HH:MM:SS` | `stat %W`, falling back to `%Y` when the filesystem has no birth time |
| `getLastAccessTime[Utc] f` / `getLastWriteTime[Utc] f` | same | `%X` / `%Y` |
| `setLastAccessTime[Utc] f v` / `setLastWriteTime[Utc] f v` | — | `v` = epoch seconds or a date string (`YYYY-MM-DD HH:MM:SS` everywhere; other forms only where `date -d` parses them: GNU, busybox); the `Utc` form reads a STRING as UTC. Implemented with `touch -t` under `TZ=UTC0`, so a value round-trips exactly |
| `setCreationTime[Utc] f v` | — | **rc 1** — a creation time cannot be set here, exactly as .NET's `File.SetCreationTime` on Unix |
| `createSymLink link target` | rc + `true`/`false` | needs a native symlink (Developer Mode or an elevated shell); a missing target, a missing link directory or an **occupied** link path is `false` + rc 1 (an existing path is never overwritten and never removed) |
| `getSymLinkTarget link` | the stored target | rc 1 for a non-link; a BROKEN link still answers |
| `open f mode` / `openRead f` / `openText f` / `openWrite f` | `f` | a "handle" is the file name; `mode` ∈ `fmOpenRead`, `fmOpenWrite`, `fmOpenReadWrite` |
| `readAllText f` / `readAllBytes f` | the content | fork-free, byte-faithful up to the first NUL |
| `readAllTextVar f NAME` | character count in `RESULT` | fills `NAME`; bad name → rc 2 |
| `readAllLines f [ARRAY]` | the text, or the line count | with `ARRAY`: fills it, RESULT = count, bad name → rc 2 |

## Encryption

`tfile.encrypt f [pw]` replaces `f` by its encryption, `tfile.decrypt f [pw]`
reverses it; `pw` defaults to `$TFILE_CRYPTO_PASSWORD`, and no password is
rc 1. Since launch L34-F2 (owner decision OG9) the file format is **KBTF1**:

| Offset | Bytes | Content |
|---|---|---|
| 0 | 5 | the magic `KBTF1` (format and version) |
| 5 | 8 | the MAC salt, random per encryption |
| 13 | 32 | the MAC: HMAC-SHA256(K_mac, bytes 0–12 ‖ CT) |
| 45 | rest | CT: exactly what `openssl enc -aes-256-cbc -salt -pbkdf2 -iter 10000 -md sha256` writes (`Salted__`, its own random 8-byte salt, the cipher blocks) |

* **K_mac** is the 32-byte key PBKDF2-HMAC-SHA256(password, MAC salt,
  10000 iterations) — what `openssl enc -aes-256-cbc -pbkdf2 -iter 10000 -md
  sha256 -S SALT -P` prints. The MAC salt is drawn independently of CT's salt,
  so the MAC key is independent of the cipher key.
* **PBKDF2: 10000 iterations, SHA-256, on both keys** — passed explicitly
  (`-iter 10000 -md sha256`), so decrypt never depends on an openssl default
  that may change between versions (10000 is today's `-pbkdf2` default).
* **decrypt checks the MAC first** and runs `openssl enc -d` only when it
  matches. A wrong password, any changed, missing or added byte (magic, salt,
  MAC or ciphertext) is **rc 1, `f` byte-identical, no temp file left**. The
  old CBC-only format had no authentication: a wrong password passed
  openssl's padding check about 1 time in 256 and `f` was replaced by garbage.
* **No legacy path.** A file without the KBTF1 header — anything written by
  the pre-L34-F2 `tfile.encrypt`, or anything else — is refused, rc 1. To
  recover such a file, decrypt it once by hand with the old command line:
  `TFILE_CRYPTO_PASSWORD=… openssl enc -d -aes-256-cbc -pbkdf2 -in OLD -out
  PLAIN -pass env:TFILE_CRYPTO_PASSWORD`.
* **The reason is one line** under `VERBOSE_KKLASS=debug` (the kcl error
  channel; silent otherwise):
  `Error: TFile.decrypt: not a tfile-encrypted file (no KBTF1 header; the pre-KBTF1 format is refused)` or
  `Error: TFile.decrypt: wrong password or a changed file (KBTF1 MAC mismatch)`;
  an unreadable `f` is `Error: TFile.encrypt|decrypt: cannot read 'f'`.
* **No secret on any command line.** The password reaches openssl only through
  its environment, under a private name (`-pass env:__TFILE_KBTF1_PW`, so a
  `readonly TFILE_CRYPTO_PASSWORD` still works); the MAC key comes back
  on openssl's stdout into a shell variable, and the HMAC (RFC 2104) is
  computed by feeding the padded key from bash's builtin `printf` into the
  stdin of `openssl dgst -sha256`, so `ps` shows neither (`-hmac KEY` would).
  Binary data travels only through files and pipes, never through `$( )`, so
  NULs and trailing newlines round-trip byte-exactly.
* **Atomic**: the result is written to an unpredictable temp file next to `f`
  and moved over `f` only on full success.
* **Caller shell options are respected**: under `set -C` (noclobber) both
  calls work; under `set -a` (allexport) the unit switches allexport off for
  the call, so neither the password nor the MAC key is exported to `mv`,
  `od`, `tail` or `mktemp`, and switches it back on; a file named `-` or
  `-x` (or in a directory `-d/`) is a file, never stdin or an option —
  openssl reads `< f`.
* **Cost**: four `openssl` processes per call (encrypt: key derivation,
  `enc`, two `dgst`; decrypt: key derivation, two `dgst`, `enc -d`) instead of
  one. On Windows Git-bash, where an `openssl` start costs ~45 ms, encrypt +
  decrypt takes ~0.53 s for 1 KB and ~0.54 s for 1 MB (it was ~0.16 s).
* **Needs** `openssl` 1.1.1 or newer (`-pbkdf2`, `-iter`), plus `od`, `tail`,
  `mktemp` and `mv`. No `openssl` → rc 1.

What it does **not** protect against (non-goals for a local file tool):

* the MAC comparison is a plain string compare in bash, **not constant-time**
  (bash cannot be);
* the password is visible to processes of the **same user** (the
  environment of the running `openssl`, `/proc/PID/environ`), and lives in
  the calling shell's memory;
* another process changing `f` **during** a call (the MAC is checked on the
  file, then the file is decrypted again);
* the file name, size (to 16 bytes) and timestamps are not hidden;
* **links**: encrypting through a **symlink** replaces the LINK by the
  encrypted file and leaves the target in plaintext; other **hard links** to
  the file keep the plaintext (the temp file is moved over the name given;
  no behaviour change is planned);
* PBKDF2 with 10000 iterations slows down a password guesser but does not
  replace a strong password.

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

`bash kcl/tfile/tests/tests.sh` — 278 cases on bash 5.2.37 and 5.3.9 (and on
the Windows and lab-VM runtimes). `007_Decrypt.sh` and `009_Encrypt.sh` hold
the KBTF1 encryption cases (launch L34-F2: refusals, the openssl HMAC oracle,
the argv and environment shims, caller shell options).
`039_Contract.sh` holds the kcl contract (`set -eu`, injection, `--` before
paths, the return contract, the locale self-heal); `040`–`043` hold the
2026-09-06 review regressions: real symlinks (G6-05, replacing 12 tests that
used to "pass as skipped"), the timestamp and attribute setters (G6-07/08/26),
the byte-faithful reads and `replace` (G6-18/19), and the D3/R8 return
contract. `tests/symlink_helper.sh` is the shared probe that asks for a NATIVE
symlink and verifies it with `[[ -L ]]`.
