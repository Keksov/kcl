# TIniFile / TMemIniFile → bash port plan (kcl/tinifile)

**Roadmap position:** 4/7 (owner priority order, 2026-07-12).
**Source of truth:** FPC `packages/fcl-base/src/inifiles.pp` — `TCustomIniFile` (:159–218), `TIniFile = class(TCustomIniFile)` (:222–259), `TMemIniFile = class(TIniFile)` (:261–269), `TIniFileOption` (:143–152), format constants (:279–283: `Brackets [] / Separator '=' / Comment ';' / LF_Escape '\'`).
**Target:** `kcl/tinifile/tinifile.sh` — kklass **instantiable** classes `TIniFile` + `TMemIniFile : TIniFile` (third kcl consumer of kklass inheritance after tstringlist/tdictionary).
**Ledger:** `kcl/tinifile/tinifile_ledger.json`.
**Workflow:** phase → dual-bash tests → full master sweep → STOP → "go"; commits gated; no unit edits during a sweep.
**Conventions:** as `kcl/tdictionary/PLAN.md` §2.2–2.4/§6.

---

## 1. Scoping analysis

INI is a line-oriented text format — the single best-fitting Pascal unit for bash in the
whole roadmap: parsing is a fork-free `while read` loop, storage is assoc arrays, and the
Read* API is **default-based, not error-based** (missing key → return the caller's
default, always rc=0), which maps perfectly onto RESULT. Practical payoff for kkbot:
config files. Entirely Tier A.

**Class mapping (mirrors FPC exactly):** in FPC BOTH classes are memory-backed;
`TIniFile` has `CacheUpdates=false` → every Write* flushes to disk; `TMemIniFile` sets
`CacheUpdates=true` → changes live in memory until explicit `UpdateFile`. The bash port
keeps this split verbatim: `TIniFile` = eager persist, `TMemIniFile : TIniFile` = cached.
`TCustomIniFile` (abstract base) is FOLDED into `TIniFile` — an abstract bash class would
be pure dispatch tax; the mapping is documented in docs/TIniFile.md.

### Ported

| FPC | bash | Notes |
|---|---|---|
| `Create(AFileName [, AOptions])` | `TIniFile.new ini <path> [optTokens]` | tokens: `ifoCaseSensitive,ifoStripQuotes,…` comma/space list (TObjectDictionary ctor style); missing file = empty ini (pin S1) |
| `ReadString(Section, Ident, Default)` | `ini.ReadString sec id default` | RESULT; always rc=0 |
| `WriteString` | `ini.WriteString sec id value` | TIniFile: + flush |
| `ReadInteger/WriteInteger`, `ReadInt64/WriteInt64` | same names | bash arith is 64-bit → Int64 == Integer path; FPC hex forms `$FF`/`0x` accepted by StrToIntDef — pin S5 |
| `ReadBool/WriteBool` | same | FPC: `CharToBool = (char='1')` :285–288, WriteBool → '1'/'0'; BoolTrueStrings/BoolFalseStrings + ifoStringBoolean — pin S6 |
| `ReadFloat/WriteFloat` | same, **string-preserving** | value passed through verbatim after shape validation; NO float engine (§2.6) |
| `SectionExists`, `ValueExists` | same | rc |
| `ReadSection` (idents), `ReadSections`, `ReadSectionValues` | `ini.ReadSection sec outArr` etc. | nameref array fills (lossless), line-echo twins |
| `EraseSection`, `DeleteKey` | same | silent-miss semantics pin S7 |
| `UpdateFile` | `ini.UpdateFile` | writes the file; order preservation §2.4 |
| `Options` property + per-option get/set | `ini.options` + tokens | subset: see §2.5 |
| `FileName` property | `ini.fileName` | read-only |
| TMemIniFile: `Clear`, `GetStrings`, `SetStrings`, `Rename(AFileName, Reload)` | same (`GetStrings/SetStrings` ↔ nameref line arrays) | |

### NOT ported (wontfix)

1. **TEncoding / BOM machinery / WriteBOM** — bash strings are bytes; UTF-8 BOM is
   TOLERATED and stripped on read, never written (documented). Other encodings out.
2. **ReadDate/ReadDateTime/ReadTime/WriteDate…** + `FormatSettings` — locale-datetime
   machinery; a dateutils bridge is possible later (out_of_scope note), v1 skips.
3. **ReadBinaryStream/WriteBinaryStream** — TStream + NUL bytes, impossible in bash.
4. **SectionList object model** (TIniFileSection/TIniFileKeyList classes) — internal
   representation, replaced by §2.2 storage.
5. **ifoEscapeLineFeeds** (`\`-continuation) — **decide at P0** after reading the FPC
   reader: if it is a simple join-on-read, port it; if it entangles the writer, wontfix v1.
6. **NUL bytes** in anything (bash limit).

---

## 2. Design decisions

### 2.1 The file-format semantics come from the FPC READER, not from folklore
INI has no RFC; the spec is `inifiles.pp`'s parser. P0 reads `FillSectionList` +
`UpdateFile` + the TIniFileSection model and pins: comment handling (are `;` lines
PRESERVED on rewrite? FPC keeps them in the section list unless ifoStripComments —
verify), blank lines, keys before any `[section]` (empty-name section?), duplicate
sections (merged? first/last?), duplicate keys in a section, whitespace around `=` and
around idents, values containing `=`, `[` in section names, inline comments (FPC: none —
`;` only at line start? verify), quoted values + ifoStripQuotes, ifoStripInvalid. Each
answer becomes a table row here and a test.

### 2.2 Storage (per instance)
- `${inst}_kv` (assoc): value store, key = `"${secKey}"$'\x1f'"${idKey}"` where secKey/idKey
  are the **lookup-normalized** names (§2.3). `\x1f` (US) cannot legally appear in a
  section/ident (validated at every public entry: rc=1; documented — the only reserved character;
  values may contain anything except NUL/newline-semantics pinned at P0).
- `${inst}_secorder` (indexed): section names in first-appearance order (original case).
- `${inst}_keyorder` (assoc): per-section `\x1f`-joined ident list in first-appearance
  order (original case) — UpdateFile round-trip preserves section/key ORDER exactly.
- Comment/blank-line preservation: storage extension decided at P0 (§2.1) — if FPC
  preserves them, a per-section raw-prefix-lines assoc keeps ours byte-compatible;
  otherwise documented divergence.
Subscripts are never empty (`\x1f` inside) → no k-prefix needed; pinned by torture test.

### 2.3 Case sensitivity — FPC default is case-INSENSITIVE
Lookups normalize section+ident with `${var,,}` unless `ifoCaseSensitive` (write-back
uses the ORIGINAL case of first appearance — classic INI behavior; pin exact FPC rule at
P0, including "does a differently-cased rewrite change the stored case?"). `${var,,}` is
locale-dependent beyond ASCII — documented (ASCII guaranteed; unicode follows the locale).

### 2.4 File I/O — fork-free, CRLF-tolerant, atomic-enough
Read: `while IFS= read -r line || [[ -n $line ]]` (handles missing final newline);
strip one trailing `$'\r'` per line (Windows INI reality); strip UTF-8 BOM on line 1.
Write (`UpdateFile`): compose in memory → single `printf '%s\n' … > "$tmp"` in the SAME
directory → `mv` over the target (the only fork on the write path is `mv`, and only in
UpdateFile — documented; a plain `>` overwrite fallback if mv unavailable is pinned at
P0). Line endings written: LF (documented; CRLF preservation NOT attempted — divergence
row if FPC differs).

### 2.5 Options subset (tokens at ctor + `options` property)
v1 targets: `ifoCaseSensitive`, `ifoStripComments`, `ifoStripInvalid`, `ifoStripQuotes`,
`ifoStringBoolean` (write '1'/'0' vs true-string), `ifoEscapeLineFeeds` (P0 decision, §1.5).
`ifoFormatSettingsActive` follows the date family → wontfix v1. Exact enum list verified
against :143–152 at P0.

### 2.6 ReadFloat/WriteFloat are string-preserving
FPC converts through Double; bash v1 validates the shape (sign/digits/point/exponent
regex pinned at P0) and passes the LITERAL through — byte-lossless, zero float deps.
Callers doing arithmetic use kcl/math. Divergence documented (FPC would canonicalize
"1.50" → "1.5"; we don't). Same philosophy as tdictionary API v2: no parity theater.

### 2.7 Error convention
INI Read* NEVER fails (default-based). Failures are structural only: bad instance/args,
`\x1f` in names, unwritable target on UpdateFile/eager Write (rc=1 + debug msg;
TIniFile eager-write failure semantics pinned at P0 — FPC raises EInOutError; we rc=1
and KEEP the memory state, documented).

## 3. Pinned semantics (P0 fills the answers)

| # | Question | FPC source anchor |
|---|---|---|
| S1 | Missing file at Create → empty ini, no error? | TIniFile.Create/ReadIniValues |
| S2 | Comments/blank lines: preserved through load→UpdateFile? Where may `;` start? | FillSectionList/UpdateFile |
| S3 | Duplicate sections / duplicate keys — merge/first/last wins? | FillSectionList |
| S4 | Keys before any `[section]`; empty section name `[]`; `]` in section | FillSectionList |
| S5 | ReadInteger accepts `$FF`/`0x`/spaces? (StrToIntDef reality) | TCustomIniFile.ReadInteger |
| S6 | ReadBool truth rule (`'1'` only? BoolTrueStrings? first char?) + WriteBool output | :285–288 + ReadBool/WriteBool |
| S7 | DeleteKey/EraseSection on missing → silent? dirty-flag set? | impl |
| S8 | Whitespace: around `=`, leading/trailing in ident and value; quoted values | FillSectionList + ifoStripQuotes |
| S9 | UpdateFile creates missing directories? (SErrCouldNotCreatePath :277) | UpdateFile |
| S10 | TIniFile eager-write: flush per Write* or on Destroy too? CacheUpdates flip mid-life? | SetCacheUpdates/MaybeUpdateFile |
| S11 | TMemIniFile.Rename(Reload=true/false) exact behavior | Rename |
| S12 | Values containing `=`, `;`, leading `[` — parse rules | FillSectionList |

## 4. Parity & test model

Seeds: FPC fcl-base tests checked at P0 (`packages/fcl-base/tests/` — tcinifile if
present, mined). Primary basis: S1–S12 source pins + round-trip properties:
load→UpdateFile idempotence (byte-compare where FPC-compatible), write→read closure for
every typed accessor, order preservation proof, case-insensitivity matrix, CRLF/BOM/
no-final-newline inputs, torture values (spaces, `=`, `;`, quotes, globs, unicode,
empty value vs absent key — ReadString default distinguishes!), `\x1f` rejects,
eager-vs-cached split (TIniFile writes disk per op; TMemIniFile only on UpdateFile —
verified via file mtime/content), GetStrings/SetStrings closure, Rename matrix,
zero-fork on all in-memory paths (PATH='' — file ops excluded by design), dual-bash.
Non-FPC cases → TEST_COVERAGE_NOTES rows.

## 5. Phases

- **P0 — reader-semantics pinning + storage freeze + skeleton.** Read FillSectionList/
  UpdateFile/typed accessors; fill S1–S12 table; freeze storage (incl. comment model);
  ctor token grammar; skeleton + runner; baseline re-measure. STOP.
- **P1 — load + read core.** File parse (CRLF/BOM/no-final-NL), ReadString,
  SectionExists/ValueExists, ReadSection/ReadSections/ReadSectionValues (fills + echo
  twins). Sweep gate. STOP.
- **P2 — write core + persistence split.** WriteString, DeleteKey, EraseSection,
  UpdateFile (order-preserving compose, tmp+mv), TIniFile eager flush vs TMemIniFile
  cached + Clear/GetStrings/SetStrings/Rename. Round-trip + idempotence proofs. Sweep
  gate. STOP.
- **P3 — typed accessors + options.** Integer/Int64 (S5), Bool (S6 + BoolStrings +
  ifoStringBoolean), Float (string-preserving), options subset behavior
  (CaseSensitive/StripComments/StripInvalid/StripQuotes[/EscapeLineFeeds]). Sweep gate. STOP.
- **P4 — docs, bench, closeout.** README (bash API, format rules AS PINNED, divergences),
  docs/TIniFile.md (upstream FPC reference per kcl docs convention, TCustomIniFile chain),
  bench.sh (load 1k keys, ReadString/WriteString hot path, UpdateFile cost),
  TEST_COVERAGE_NOTES finalized, ledger COMPLETE, final sweep. STOP.

## 6. Bash traps to respect

1. `read` without `-r` mangles backslashes — ALWAYS `-r`; `IFS=` to keep edge spaces.
2. Last line without `\n`: `|| [[ -n $line ]]` or the value silently drops.
3. `${var,,}` beyond ASCII is locale-dependent — document; tests use ASCII + a pinned
   unicode observation row.
4. `\x1f` composite keys: validate at EVERY public entry (Write*, Delete*, Erase*).
5. Assoc idioms: existence `${ref[key]+x}`, deletion via single-quoted `unset 'ref[$k]'`
   (tdictionary pins); keys here are never empty by construction (`\x1f` inside).
6. Empty value vs absent key are DIFFERENT (default must not mask stored ''): the
   tdictionary GetValueDef lesson, re-pinned here.
7. `kk._return ""` on func fail paths (kklass trailer trap).
8. Writer must not `echo` values (dash/backslash mangling) — `printf '%s'` only.
9. Never edit the unit mid-sweep (house rule).

## 7. Deliverables

`kcl/tinifile/`: tinifile.sh, PLAN.md, tinifile_ledger.json, README.md,
docs/TIniFile.md, bench.sh, TEST_COVERAGE_NOTES.md, tests/001…+tests.sh.
