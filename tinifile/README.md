# kcl/tinifile — TIniFile / TMemIniFile for bash

A faithful bash port of FPC `fcl-base` `inifiles.pp`: **`TIniFile`** (eager —
every write hits disk) and **`TMemIniFile : TIniFile`** (cached — changes live
in memory until `UpdateFile`, or a dirty-on-destroy auto-flush). kklass
instantiable classes, so you make instances and call methods:

```bash
source kcl/tinifile/tinifile.sh

TMemIniFile.new cfg ~/.myapp.ini          # cached; loads the file if present
cfg.WriteString  server host  example.com
cfg.WriteInteger server port  8080
cfg.WriteBool    server tls   true
cfg.UpdateFile                            # one atomic write

cfg.ReadString  server host  localhost    # -> RESULT="example.com"
cfg.ReadInteger server port  80           # -> RESULT=8080
cfg.ReadBool    server tls   0            # -> RESULT=1
cfg.delete

TIniFile.new eager /etc/app.ini           # every Write* flushes immediately
```

The INI format has no RFC — **its spec is the FPC reader**
(`FillSectionList`). Every rule below was pinned from the source at P0 and is
enforced by a test; divergences from FPC are called out explicitly. INI is the
best-fitting Pascal unit for bash in the roadmap: a fork-free `while read`
parse, sparse-array storage, and a **default-based** Read API (a missing key
returns the caller's default, always rc 0) that maps cleanly onto `RESULT`.

## The two classes (FPC-verbatim split)

| | storage | write timing | auto ifoStripQuotes | on destroy |
|---|---|---|---|---|
| **TIniFile** | memory | **eager** — each Write*/DeleteKey(hit)/EraseSection(hit) flushes | **yes** (FPC :967) | (nothing pending — already flushed) |
| **TMemIniFile** | memory | **cached** — marks dirty; writes on `UpdateFile` | no | **auto-flush if dirty** (FPC :1024, errors eaten) |

`TCustomIniFile` (FPC's abstract base) is FOLDED into `TIniFile` — an abstract
bash class would be pure dispatch tax. Mapping documented in
[docs/TIniFile.md](docs/TIniFile.md).

## Format rules — as pinned from the FPC reader

- **Comment** = a line whose first non-space char is `;`. No inline comments
  (`a=b ; c` → value is `b ; c`). Comments are PRESERVED across load→UpdateFile
  (a comment before any section becomes a comment-section; inside a section, a
  comment-key) unless `ifoStripComments`.
- **Blank lines** are dropped on load; `UpdateFile` re-inserts one blank line
  between sections (not after a comment-section). `GetStrings` differs by one
  detail: a blank after *every* section (FPC :1486).
- **Duplicates** (sections or keys) are all kept; every lookup is a linear
  first-appearance scan — **first wins**; `WriteString` updates the first
  match; `UpdateFile` emits all copies.
- **`[]`** = a section with the empty name: stored, rewritten, and listed by
  `ReadSections` as `""`, but **not addressable** (lookups reject empty names).
  `]` is legal inside a name (`[a]b]` → `a]b`).
- **Key parsing**: each line is trimmed; ident = trim(before first `=`), value
  = trim(after). A line with no `=` inside a section is an *invalid* row
  (ident `""`, value = the line), kept unless `ifoStripInvalid`. Keys before
  any section are silently dropped.
- **Quotes**: stored verbatim, stripped only at READ (matching `"…"`/`'…'`,
  length > 1) when `ifoStripQuotes`. TIniFile strips by default; TMemIniFile
  does not (opt in with the token).
- **CRLF / BOM / no final newline**: tolerated on read (one trailing `\r`
  stripped per line, UTF-8 BOM stripped from line 1). Written line ending is
  **LF**.
- **UpdateFile** creates missing parent directories (FPC `ForceDirectories`),
  writes to a temp file in the same dir, then `mv`s over the target (atomic
  enough); on failure it returns rc 1 and **keeps the in-memory state**,
  `dirty` included, and removes the temp file on every failure branch. It
  refuses before touching anything when the target is a **directory** or an
  existing **read-only** file — FPC's `SaveToFile` raises in both cases, while
  `mv` would happily move the temp file *into* the directory, or replace the
  read-only file and reset its mode. A `\` in `file_name` is a separator: the
  path is normalised for every filesystem operation (the variable itself keeps
  the caller's text), so `C:\dir\x.ini` gets the same ForceDirectories
  treatment as `C:/dir/x.ini` on both MSYS and cygwin.

## API

Read family (never fail — rc 0, missing → default):
`ReadString sec id default` · `ReadInteger`/`ReadInt64 sec id default` ·
`ReadBool sec id default(0|1)` · `ReadFloat sec id default` ·
`SectionExists sec` (rc 0/1) · `ValueExists sec id` (rc 0/1). Array fillers
(FUNC, `RESULT`=count, fill a caller nameref — **call directly**):
`ReadSection sec arr` · `ReadSections arr` · `ReadSectionValues sec arr [svo…]`
· `ReadSectionRaw sec arr`.

**`SectionExists` is FPC's `Assigned(S) and not S.Empty`**: a section with no
keys, or with comment keys only, does **not** exist — while one holding an
*invalid* row (a line without `=`) does, because `IsComment('')` is false. The
section is still listed by `ReadSections` and still readable; only the
predicate says no. `WriteString` + `DeleteKey` therefore leaves a listed
section that reports "does not exist".

Write family: `WriteString sec id value` · `WriteInteger`/`WriteInt64` ·
`WriteBool` · `WriteFloat` · `DeleteKey sec id` · `EraseSection sec` ·
`UpdateFile` · `SetBoolStringValues true|false v1 [v2…]`. On an **eager**
`TIniFile` every one of them flushes, and the flush's rc is the member's rc —
`DeleteKey`/`EraseSection` included (a miss changes nothing and is still rc 0).

### Output/input array names (rc 2)

Every member that takes the **name** of a caller array — `ReadSection`,
`ReadSections`, `ReadSectionValues`, `ReadSectionRaw`, `GetStrings`,
`SetStrings` — validates it before binding the nameref and answers **rc 2**
(malformed call, `RESULT=""`, nothing written, nothing printed) for anything
that is not a plain non-associative identifier or that is reserved:

`__tif_*` · `__kk_*`/`__KK_*` · `RESULT` · `REPLY` · `IFS` · `this` ·
`__inst__` · `__class__` · `state` · the four instance variables **`file_name`,
`options`, `cache_updates`, `dirty`** · the instance's own storage arrays
(`<inst>_secnames`, `_snorm`, `_secbrk`, `_srows`, `_sblob`, `_kident`,
`_knorm`, `_kvalue`, `_kowner`, `_ctr`, `_booltrue`, `_boolfalse`, `_data`,
`_class`). The instance variables are reserved because inside a member body
they are namerefs into the instance's data: `ini.ReadSections dirty` used to
resolve to the instance's own `dirty` flag.

TMemIniFile extras: `Clear` · `GetStrings arr` · `SetStrings arr` ·
`Rename newName [reload]`.

Vars: `file_name` · `options` (space-joined tokens) · `cache_updates` ·
`dirty`.

### Typed conversions (pinned)

- **Integer** (`ReadInteger`/`ReadInt64`) = FPC `StrToIntDef`/`val()`, ported
  from `InitVal` (`rtl/inc/sstrings.inc:1086`) and `fpc_Val_SInt_ShortStr`
  (:1141) rule by rule: **leading spaces and TABs are skipped**, then a sign,
  then a base prefix — `$FF`, `0x1A`/`0X1A`, and a **bare `x`/`X`** (`x1F` is
  31, which surprises everyone but is what `InitVal` does), `&17` (octal),
  `%1010` (binary) — then leading zeros are dropped; a leading-zero decimal
  stays DECIMAL (`0123`→123, not octal). Anything else, a **trailing** blank
  included, is a conversion error → default. An **out-of-range** literal is an
  error too, not a wrap: `99999999999999999999` and `$FFFFFFFFFFFFFFFFFFFF`
  return the default. Non-decimal literals are accepted up to `MaxUIntValue`
  and reinterpreted as a signed Int64, so `$FFFFFFFFFFFFFFFF` is `-1` — FPC's
  own sign extension. `WriteInteger` stores canonical decimal (`$FF`→`255`,
  `' x1F'`→`31`) and refuses what `val()` refuses.
- **Bool** (`ReadBool`) cascade: (1) if any BoolStrings list is set →
  case-insensitive membership, true-list then false-list, else default; (2)
  elif `ifoStringBoolean` → case-insensitive `true`/`false`, else default;
  (3) else first char `== '1'`. Empty value → default. `WriteBool` writes
  `1`/`0`, or (with `ifoStringBoolean`) `BoolTrueStrings[0]`//`true` /
  `BoolFalseStrings[0]`//`false`.
- **Float** is **string-preserving**: shape-validated, stored/returned
  verbatim. No Double round-trip, no float engine — callers doing arithmetic
  use `kcl/math`.

## Locale

The case-insensitive lookup is `${x,,}`, which folds `É`→`é` only under a
UTF-8 locale — so a UTF-8 locale is part of this unit's contract (kcl decision
D6). The test runners pin `LC_ALL=C.UTF-8`, and the unit **self-heals a bare
environment** at load time: if `LC_ALL`, `LC_CTYPE` and `LANG` are all empty it
exports `LC_CTYPE=C.UTF-8`. An explicit locale is never overridden — under
`LC_ALL=C` ASCII names still fold and accented ones do not, which is the
caller's choice. Values are byte strings throughout and round-trip verbatim in
any locale.

## Options

Ctor tokens (comma/space irrelevant — pass as separate args), also settable
via the `options` var: `ifoCaseSensitive`, `ifoStripComments`,
`ifoStripInvalid`, `ifoStripQuotes`, `ifoStringBoolean` (alias
`ifoWriteStringBoolean`), `ifoEscapeLineFeeds` (read-side `\`-continuation
join). `ifoFormatSettingsActive` and the date family are **not** supported.
Unknown token → rc 1, but the instance is valid with the tokens accepted so
far.

## Divergences from FPC (all deliberate, all tested)

| Topic | FPC | here |
|---|---|---|
| Float values | canonicalized through Double (`1.50`→`1.5`) | **string-preserving** (`1.50` kept) — lossless, zero float deps |
| Integer width | ReadInteger clamps to 32-bit Longint | 64-bit (== ReadInt64); no clamp |
| Write of empty/`;`-leading/`=`-in-ident names | silent no-op, later misreads | **rejected rc 1** (fail-fast over silent corruption) |
| CR/LF inside a value | written, corrupts the file | **rejected rc 1** |
| Write of a `[`-leading ident with a `]`-ending value | written; the next read takes `[list=1,2]` for a **section header**, the key vanishes and the keys after it migrate | **rejected rc 1** (hybrid rule: refuse on write what the reader would reinterpret) |
| Write of a value ending in `\` under `ifoEscapeLineFeeds` | written; the next read joins the following key onto it (`C:\App\` swallows `name=x`) | **rejected rc 1** — without the option the same value is fine |
| `[;name]` section | loads as the section named `;name`, then `UpdateFile` writes it back as a bare comment and every key it owned is orphaned | loader unchanged (FPC-verbatim); the **composer keeps the brackets**, so the round trip is stable |
| `UpdateFile` onto a directory / a read-only file | `SaveToFile` raises | **rc 1**, memory and `dirty` kept, no temp file left |
| Line endings | platform | always LF |
| Date/time, binary streams, encodings/BOM-write | supported | **wontfix** (bash byte strings; use `kcl/dateutils`/`kcl/math` for values) |

## Tests & bench

`tests/001…012` — **191 cases**, green on bash 5.2.37 **and** true 5.3.9:
skeleton + ctor split (001), load/read core over an S-pin torture fixture incl.
UTF-8 (002), write core + persistence + round-trip idempotence (003), typed
accessors (004), **the complete FPC `utcinifile.pp` Bool seed — all 16
assertions verbatim** (005), the kcl contract smoke test (006), and the five
files added by the 2026-09-06 review: persistence edges (007 — directory
target, read-only target, `-`-leading name, temp-file cleanup on every failure
branch, eager delete rc, `\`-paths), the two round-trip corruptions and
`SectionExists` (008), `ifoEscapeLineFeeds` plus the whole `val()` grammar
(009), output-array names (010) the relative cost gates (011) and the D6 locale self-heal in a child shell with the locale cleared (012). Per-case
rationale in [TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md).

`bench.sh` reports load / ReadString / WriteString / UpdateFile costs (timed
via `TStopwatch`) and, since P8, the two **relative** shape gates the review
asked for: 800 appends under 10× 200 appends, a lookup in the 20th section
under 3× one in the first. The port keeps FPC's linear first-match model, so
lookups are still O(keys in the section) — but nothing is O(all keys) any more
and a miss (which is what every append does first) costs one substring test.
