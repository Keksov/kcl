# kcl/tcustomapplication — TCustomApplication for bash

A bash port of Free Pascal's `CustApp.TCustomApplication` as a kklass
**instance** class: an application object that owns a command line, parses it
the way FPC does, and runs a `DoRun` loop until it is terminated.

Upstream source of truth: FPC 3.2.2
[`packages/fcl-base/src/custapp.pp`](https://gitlab.com/freepascal.org/fpc/source/-/raw/release_3_2_2/packages/fcl-base/src/custapp.pp).
The option parser is a line-by-line port of that file (decision **D4**, phase P4
of the 2026-09-06 review).

```bash
source kcl/tcustomapplication/tcustomapplication.sh

TCustomApplication.new app "$@"          # or: TCustomApplication.new app; app.SetArgs "$@"

declare -a files=()
app.CheckOptions "hvc:" "help version config:" || :
if [[ -n "$RESULT" ]]; then
    printf '%s\n' "$RESULT" >&2      # FPC's message, e.g.
    exit 1                           #   Invalid option at position 2: "x"
fi
if app.HasOption h help; then usage; exit 0; fi
app.GetOptionValue c config; cfg="$RESULT"
app.GetNonOptions "hvc:" "help version config:" files
app.delete
```

## The argument vector

`Params` is indexed exactly as FPC's `ParamStr`:

| index | value |
|---|---|
| `0` | the executable name — `$0`, the same value as `ExeName` |
| `1 … ParamCount` | the arguments, in order |
| anything else | `''` |

Nothing is captured automatically. An application is given its command line by
`TCustomApplication.new app "$@"` or `app.SetArgs "$@"`, and a fresh instance
has `ParamCount` 0 (before P4 the *first option method called* stored its own
parameters as the application's argv — finding TCA-04). `SetArgs` stores its
arguments verbatim, `--` included; it has no separator of its own (TCA-13).

Every index in this unit — `FindOptionIndex`, `GetOptionAtIndex` and the
`position` in an error message — is that 1-based `ParamStr` index.

## Option syntax (FPC, not getopt)

| written | meaning |
|---|---|
| `-x` | short option `x` |
| `-xyz` | the cluster `x`, `y`, `z` |
| `-x value` | `x` takes the next argument, **if** the spec says it takes one |
| `--name` | long option `name` |
| `--name=value` | long option `name` with a value — **the only** long value syntax |
| `--name value` | long option `name`, and `value` is a separate non-option |
| `-` | too short to name an option: `Invalid option at position N: "-"` |
| `--` | a long option with an empty name: `Invalid option at position N: ""` |

The option specification is getopt-shaped:

| spec | meaning |
|---|---|
| `x` / `name` | a switch; a value is an error (`SErrNoOptionAllowed`) |
| `x:` / `name:` | a value is **required** (`SErrOptionNeeded` when missing) |
| `x::` / `name::` | a value is optional |

A short option that takes a value must be **last** in its cluster: `-cv x` with
the spec `c:v` is `Option at position 1 needs an argument : c`, while `-vc x`
is accepted and `x` is consumed by `c`.

`FindOptionIndex` scans **downward** from `ParamCount`, so the **last**
occurrence of an option wins (default R10; that is what FPC 3.2.2 does).
`StartAt` is the highest index to consider: `StartAt` 0 finds nothing, and the
way to walk every occurrence is to pass `index - 1` after each hit.

## API

`obj` below is an instance created with `TCustomApplication.new obj [ARGS…]`.

| Member | Arguments | Returns |
|---|---|---|
| `TCustomApplication.new obj [ARG…]` | the application's argv | the instance |
| `obj.delete` | | frees the instance and its argv |
| `obj.Initialize` | | `Terminated = false` |
| `obj.SetArgs [ARG…]` | the new argv, verbatim | replaces the stored argv |
| `obj.ParamCount` | | `RESULT` = number of arguments |
| `obj.Params INDEX` | 0 = `ExeName` | `RESULT` = that argument, `''` past the end; rc 1 for a non-numeric index |
| `obj._GetArgs` | | `RESULT` = `ParamCount` (kept as an alias) |
| `obj.FindOptionIndex SHORT LONG [STARTAT]` | either name may be `''` = "not given" | `RESULT` = index or `-1`; rc 1 for a non-numeric `STARTAT` |
| `obj.GetOptionAtIndex INDEX ISLONG` | `ISLONG` = `true`/`false` | `RESULT` = the option's value |
| `obj.GetOptionValue SHORT LONG` | short name tried first | `RESULT` = value or `''` |
| `obj.GetOptionValues SHORT LONG [ARRAY]` | `ARRAY` = name of a caller array | `RESULT` = count; rc 2 for a bad array name |
| `obj.HasOption SHORT LONG` | | **rc 0/1**, and `true`/`false` in `RESULT` |
| `obj.CheckOptions SHORT LONG [OPTS\|ALLERRORS] [NONOPTS] [ALLERRORS]` | see below | `RESULT` = `''` or the error message(s); rc 2 for a bad array name |
| `obj.GetNonOptions SHORT LONG [ARRAY]` | | `RESULT` = count; **rc 1** when the command line has any error |
| `obj.Terminate [EXITCODE]` | | sets `Terminated`, and the global `EXITCODE` when given; rc 1 for a non-numeric code |
| `obj.DoRun` | | the application body — override it; the base class terminates |
| `obj.Run` | | calls `DoRun` until `Terminated` |
| `obj.HandleException SENDER [MESSAGE]` | | `OnException` or `ShowException`, then `Terminate` if `StopOnException` |
| `obj.ShowException MESSAGE` | | `Exception: MESSAGE` on **stderr** |
| `obj.GetEnvironmentList ARRAY [NAMESONLY]` | | fills the array, `RESULT` = count; rc 2 for a bad array name |
| `obj.Log TYPE FMT [ARG…]` | | one `TYPE: message` line on **stderr**, filtered by `EventLogFilter` |
| `obj.ConsoleApplication` | | `RESULT` = `true` |
| `obj.Location` | | `RESULT` = the directory of `$0` |
| `obj.EnvironmentVariable NAME` | | `RESULT` = the value; rc 1 unless `NAME` is a plain identifier |

Stored properties, read as `obj.<Name>` (inside `$( )`) or written with
`obj.property <Name> = <value>`:

| Property | Default | Meaning |
|---|---|---|
| `Terminated` | `false` | `Run` stops when this is `true` |
| `Title` | `Application` | free-form |
| `HelpFile` | `''` | free-form |
| `OptionChar` | `-` | the character that introduces an option |
| `CaseSensitiveOptions` | `true` | `false` folds case on both sides |
| `StopOnException` | `true` | `HandleException` terminates the application |
| `ExceptionExitCode` | `1` | the code `HandleException` terminates with |
| `OnException` | `''` | the name of a shell **function** `f SENDER MESSAGE` |
| `EventLogFilter` | `''` | space- or comma-separated event types; empty = log everything |
| `ExeName` | `$0` | read-only (computed) |

### `CheckOptions` parameters

```bash
obj.CheckOptions SHORT LONG [OPTS] [NONOPTS] [ALLERRORS]
obj.CheckOptions SHORT LONG [ALLERRORS]           # 3rd parameter exactly true/false
```

* `SHORT` — the getopt-style string, e.g. `"hvc:o::"`.
* `LONG` — either the **name of an array** of long options, or a string of them
  separated by spaces, tabs, CR or LF (FPC's two overloads; which one is meant
  is decided by `LONG` alone — finding TCA-08).
* `OPTS` — name of an array that receives `name=value` for every option that
  actually **took** a value. FPC adds nothing else: two switches leave it empty.
* `NONOPTS` — name of an array that receives the non-option arguments.
* `ALLERRORS` — `true` keeps parsing after the first error and joins every
  message with a newline; the default `false` stops at the first one.

Error texts are FPC's `ResourceString`s verbatim:

```
Invalid option at position %d: "%s"
Option at position %d does not allow an argument: %s
Option at position %d needs an argument : %s
```

## Contract

This unit follows the [kcl contract](../README.md#1-the-kcl-contract):

- **Values come back in `RESULT`.** A direct call prints nothing; `$(obj.x)`
  prints the value exactly once but forks. Values are data — `-e`, `-n`,
  embedded newlines and backslashes round-trip (`printf`, never `echo`).
- **Sequences go into a caller array by name, with the count in `RESULT`**
  (`GetOptionValues`, `GetNonOptions`, `CheckOptions`, `GetEnvironmentList`).
  The name is validated; a reserved or malformed name is **rc 2** and nothing
  is written.
- **`HasOption` answers with `rc`** and also leaves `true`/`false` in `RESULT`
  (default R8). Under `set -e` call it from an `if`, a `&&`/`||` or a `!`.
- **Errors are rc 1 + `RESULT=''`**, silent unless `VERBOSE_KKLASS=debug`.
  `GetNonOptions` is the one member that fails on a bad command line — FPC
  raises `EListError` there.
- **Numeric arguments** (`Params INDEX`, `FindOptionIndex … STARTAT`,
  `GetOptionAtIndex INDEX`, `Terminate CODE`) go through `kk.isInt` before any
  arithmetic (decision D1): `x[$(touch pwn)]` is rejected, not executed.
- **`set -eu` clean**, loadable and re-loadable.
- **No forks.** The parser is eight plain shell functions with no command
  substitution, no pipe and no external command; `031_Contract.sh` asserts that
  structurally and checks `BASHPID` across a call. The one exception is
  `GetEnvironmentList`, which needs one process substitution to read
  `compgen -e`.
- **UTF-8**: the unit exports `LC_CTYPE=C.UTF-8` when `LC_ALL`, `LC_CTYPE` and
  `LANG` are all empty, because `CaseSensitiveOptions=false` folds case.

## Differences from FPC

Everything below is deliberate; anything not listed here is FPC's behaviour.

1. **`FindOptionIndex` takes a (short, long) pair.** FPC has one name per call
   plus a `var LongOpt` out-parameter, and its callers try the short name and
   then the long one. The port merges that into every member's `SHORT LONG`
   signature; an empty name means "not given" and is not searched (FPC passes
   the impossible character `#255` for the same purpose).
2. **`GetOptionAtIndex` is public.** It is `protected` in FPC; the merge above
   hides which of the two names matched, so the member is exposed.
3. **`GetNonOptions` returns rc 1** where FPC raises `EListError`; the output
   array is left untouched (decision D2).
4. **`Location` has no trailing separator.** FPC's `ExtractFilePath` keeps one
   (`/a/b/`); this returns `/a/b`, and `.` when `$0` has no directory part —
   the same convention as `tpath.getDirectoryName`.
5. **`Log` writes to stderr.** FPC's `DoLog` is empty and descendants override
   it; a bash port has to do *something*, and a log line is a diagnostic.
6. **`Run` treats a non-zero status from `DoRun` as an exception** and passes it
   to `HandleException`; bash has no exceptions. The base `DoRun` **terminates**
   the application — FPC's is empty, which would make the inherited `Run` spin
   forever.
7. **`Terminate` sets a plain global `EXITCODE`.** FPC assigns the program
   variable `ExitCode`. It is deliberately **not exported** (finding TCA-12).
8. **`GetEnvironmentList` enumerates `compgen -e`**, so its order is bash's, not
   the environment's, and names that are not valid shell identifiers (MSYS puts
   a few in the environment) are skipped. FPC does not sort either.
9. **Defaults**: `StopOnException` is `true`, `ExceptionExitCode` is `1` and
   `Title` is `Application`. FPC leaves them `False`, `0` and `''`. These are
   the port's long-standing values and are kept so that an unhandled error in a
   script stops it.
10. **A value-taking option in a cluster does not corrupt the scan.** FPC's
    `CheckOptions` assigns `O := O[j]` inside the loop and then keeps indexing
    `O[j]` against the *original* length, which reads past the end of the string
    (`-cv` with the spec `c::v` is enough to trigger it). The port keeps the
    scan string intact and records the consuming option separately, which is
    identical to FPC for every input where FPC stays in bounds.
11. **`SetArgs` is not in FPC** at all — FPC reads the real process command
    line. It is how a bash application gets one.

## Tests

```bash
bash kcl/tcustomapplication/tests/tests.sh
bash kcl/tcustomapplication/tests/tests.sh --verbosity info
```

`docs/TCustomApplication.md` is the upstream FPC reference; its header maps
each documented member onto this port.
