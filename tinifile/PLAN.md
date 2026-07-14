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
5. **ifoEscapeLineFeeds** — RESOLVED AT P0: it is a simple READ-side join
   (RemoveBackslashes :1039 merges `\`-terminated lines before parsing; the
   writer emits the joined form) → **PORTED**.
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

### 2.2 Storage (per instance) — REVISED AT P0: the FPC section-list, verbatim
The originally-planned assoc `kv["sec\x1fid"]` model CANNOT represent S3
(duplicate sections/keys both stored, first-wins, all emitted) — so P0 froze a
direct mirror of FPC's TIniFileSectionList instead, as parallel SPARSE indexed
arrays with linear scans (FPC itself scans linearly — KeyByName/SectionByName
are for-loops; config-file scale, and the P4 bench arbitrates if it ever hurts):
- `${inst}_secnames` (indexed, sparse): one slot per section IN ORDER — a slot
  may hold a comment-section (text starts `;`) or the empty name (`[]`).
- `${inst}_kident` / `${inst}_kvalue` / `${inst}_kowner` (indexed, sparse,
  parallel): one row per key IN ORDER — comment-keys (ident `;…`, value ''),
  invalid rows (ident '', value = raw line), normal keys; kowner = owning
  section SLOT.
- Deletion = `unset` the slot/row (sparse holes; iteration via `${!arr[@]}`
  preserves order; no renumbering, no compaction at config scale).
- Duplicates, order fidelity, comment preservation and the `[]`-section all
  come FREE — byte-compatible UpdateFile output by construction.
- The `\x1f` reserved-character constraint is GONE (no composite keys).
- Case: lookups compare normalized (`${x,,}`) unless ifoCaseSensitive; slots
  store ORIGINAL first-appearance case; WriteString updates the first match
  in place (stored ident case unchanged) — exactly FPC.

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

### 2.7 Error convention + write-path validation (P0-frozen)
INI Read* NEVER fails (default-based). Failures are structural only: bad
instance/args and unwritable target on UpdateFile/eager Write (rc=1 + debug
msg; FPC raises EInOutError; we rc=1 and KEEP the memory state, documented).
**Validation hardening (documented divergence — fail-fast over silent
corruption):** WriteString and friends reject with rc=1 what FPC would write
and then MISREAD after reload: empty Section/Ident (FPC silently no-ops — we
add the debug message), Ident containing `=` or starting with `;`, Section
starting with `;`, and CR/LF anywhere in Section/Ident/Value (line-based
format). FPC happily corrupts in all these cases; round-trip integrity is this
unit's core promise, so we refuse instead. Values may otherwise contain
anything (`=`, `;`, quotes, `[`, unicode, spaces — all pinned by S8/S12).

## 3. Pinned semantics — ANSWERED at P0 (2026-07-13, from inifiles.pp source)

| # | Answer | Anchor |
|---|---|---|
| S1 | Missing file → EMPTY ini, no error (`FileExists` guard). | ReadIniValues :1411 |
| S2 | Comment = line whose FIRST char after Trim is `;` (leading spaces then `;` IS a comment; no inline comments — `;` after a value is part of the value). PRESERVED: before any section → a comment-SECTION (Name=the line); inside a section → a comment-KEY (Ident=line, Value=''); stripped only under ifoStripComments. **Blank lines are DROPPED on load**; UpdateFile inserts ONE blank line between sections (not after comment-sections). | IsComment :298, FillSectionList :1076/:1094, UpdateFile :1373 |
| S3 | Duplicates BOTH stored (sections and keys); every lookup is a linear scan, **FIRST wins** (Break); WriteString updates the FIRST match; UpdateFile emits ALL copies. | SectionByName/KeyByName (Break), FillSectionList |
| S4 | Non-comment key lines BEFORE any `[section]` are **silently DROPPED**. `[]` → section with Name='' — stored, rewritten as `[]`, listed by ReadSections as '' — but **NOT addressable** (SectionByName/KeyByName guard `AName>'' and not IsComment`). `]` inside a name is fine: `[a]b]` → name `a]b` (only first `[` / last char `]` matter, after Trim). | FillSectionList :1086, guards :460/:536 |
| S5 | ReadInteger/Int64 = StrToIntDef via val(): optional sign + decimal \| `$`hex \| `0x/0X`hex \| `&`octal \| `%`binary; anything else → Default. Whitespace inside → invalid (line already trimmed by parser). | :690–707 + val() |
| S6 | ReadBool cascade: (1) if BoolTrue/FalseStrings set → exact-match lists (SameText), no match → Default; (2) elif ifoWriteStringBoolean (=ifoStringBoolean, alias :272) → SameText 'true'/'false', else Default; (3) else `first char == '1'`. Empty value → Default. WriteBool: option → BoolTrueStrings[0]//'true' / BoolFalseStrings[0]//'false'; else '1'/'0'. | :720–772, CharToBool :285 |
| S7 | DeleteKey: silent when section/key missing; flush(Maybe) ONLY when actually deleted. EraseSection: silent when missing; found → whole section object removed (its comment-keys die with it) + MaybeUpdateFile. | :1318–1347 |
| S8 | Every LINE is Trim'd first; ident = Trim(before FIRST `=`), value = Trim(after). Quotes are STORED verbatim; stripped only at READ (ReadString/ReadSectionValues) when StripQuotes: matching `"…"`/`'…'`, len>1. **TIniFile.Create AUTO-ADDS ifoStripQuotes; TMemIniFile does NOT** (`if not (self is TMemIniFile)` :969). WriteString never quotes. | FillSectionList :1114, ReadString :1136, Create :967 |
| S9 | UpdateFile: ForceDirectories(dir of FileName) — **CREATES missing directories**; failure → EInOutError (bash: rc=1, memory kept). After write it RE-PARSES the composed lines and clears Dirty. | :1377–1391 |
| S10 | MaybeUpdateFile: CacheUpdates ? Dirty:=true : UpdateFile. TIniFile: CacheUpdates=false → EVERY Write*/Delete(hit)/Erase(hit) flushes. TMemIniFile ctor: CacheUpdates=true. SetCacheUpdates(false) while dirty → flush. **Destroy: flushes when Dirty AND CacheUpdates, exceptions eaten** (D7 compat, bug 19046). | :1151, :1397, :1447, Destroy :1024 |
| S11 | Rename(AFileName, Reload): FFileName:=new, FStream:=nil; Reload → ReadIniValues from the NEW file (missing → empty); no write happens. | :1494 |
| S12 | Value = everything after the FIRST `=` (trimmed): may contain `=`, `;`, `[`, quotes. Line with NO `=` inside a section → "invalid" key: Ident='', Value=line — kept unless ifoStripInvalid; ReadSection lists it as '' (IsComment('')=false); ReadSectionValues includes it by default (svoIncludeInvalid). | FillSectionList :1104–1116, ReadSection :1211 |

**Extra pins (beyond the S-table):** WriteString guard: empty Section OR empty Ident → NO-OP (FPC :1179; we add rc=1+debug). ifoEscapeLineFeeds = READ-side only (RemoveBackslashes joins `\`-terminated lines BEFORE parsing; UpdateFile writes the JOINED form) → **PORTED** (simple join loop; §1.5 resolved). ReadSectionValues option-quirks: comments included if svoIncludeComments OR ifoStripComments; invalid if svoIncludeInvalid (default) OR ifoStripInvalid. GetStrings ≠ UpdateFile by one detail: blank line after EVERY section incl. comment-sections. SetStrings/Clear do NOT touch Dirty. UpdateFile writes `Ident=Value` with NO spaces and the section header `[Name]`; comment-sections/keys emit their text verbatim. FormatSettings defaults (DecimalSeparator '.') pinned :605–615 — relevant only as documentation (floats are string-preserving here).

## 4. Parity & test model

Seeds: **FOUND at P0** — `packages/fcl-base/tests/utcinifile.pp` (fpcunit; small:
2 dense Bool tests = 16 assertions over WriteBool/ReadBool incl. BoolStrings +
ifoWriteStringBoolean, on a TMemIniFile) — mined verbatim at P3 (typed
accessors); everything else has NO FPC test. Primary basis: S1–S12 source pins
+ round-trip properties:
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
