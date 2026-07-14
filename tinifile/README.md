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
  enough); on failure it returns rc 1 and **keeps the in-memory state**.

## API

Read family (never fail — rc 0, missing → default):
`ReadString sec id default` · `ReadInteger`/`ReadInt64 sec id default` ·
`ReadBool sec id default(0|1)` · `ReadFloat sec id default` ·
`SectionExists sec` (rc 0/1) · `ValueExists sec id` (rc 0/1). Array fillers
(FUNC, `RESULT`=count, fill a caller nameref — **call directly**):
`ReadSection sec arr` · `ReadSections arr` · `ReadSectionValues sec arr [svo…]`
· `ReadSectionRaw sec arr`.

Write family: `WriteString sec id value` · `WriteInteger`/`WriteInt64` ·
`WriteBool` · `WriteFloat` · `DeleteKey sec id` · `EraseSection sec` ·
`UpdateFile` · `SetBoolStringValues true|false v1 [v2…]`.

TMemIniFile extras: `Clear` · `GetStrings arr` · `SetStrings arr` ·
`Rename newName [reload]`.

Vars: `file_name` · `options` (space-joined tokens) · `cache_updates` ·
`dirty`.

### Typed conversions (pinned)

- **Integer** (`ReadInteger`/`ReadInt64`) = FPC `StrToIntDef`/`val()`: sign +
  decimal | `$FF` | `0x1A` | `&17` (octal) | `%1010` (binary); a leading-zero
  decimal stays DECIMAL (`0123`→123, not octal); anything else → default.
  `WriteInteger` stores canonical decimal (`$FF`→`255`).
- **Bool** (`ReadBool`) cascade: (1) if any BoolStrings list is set →
  case-insensitive membership, true-list then false-list, else default; (2)
  elif `ifoStringBoolean` → case-insensitive `true`/`false`, else default;
  (3) else first char `== '1'`. Empty value → default. `WriteBool` writes
  `1`/`0`, or (with `ifoStringBoolean`) `BoolTrueStrings[0]`//`true` /
  `BoolFalseStrings[0]`//`false`.
- **Float** is **string-preserving**: shape-validated, stored/returned
  verbatim. No Double round-trip, no float engine — callers doing arithmetic
  use `kcl/math`.

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
| Line endings | platform | always LF |
| Date/time, binary streams, encodings/BOM-write | supported | **wontfix** (bash byte strings; use `kcl/dateutils`/`kcl/math` for values) |

## Tests & bench

`tests/001…005` — 84 cases, green on bash 5.2.37 **and** true 5.3.9: skeleton
+ ctor split (001), load/read core over an S-pin torture fixture incl. UTF-8
(002), write core + persistence + round-trip idempotence (003), typed
accessors (004), and **the complete FPC `utcinifile.pp` Bool seed — all 16
assertions verbatim** (005). Per-case rationale in
[TEST_COVERAGE_NOTES.md](TEST_COVERAGE_NOTES.md). `bench.sh` reports load /
ReadString / WriteString / UpdateFile costs (timed via `TStopwatch`).
