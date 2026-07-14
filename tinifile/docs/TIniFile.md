# TIniFile / TMemIniFile — upstream FPC API reference

Source of truth: FPC `packages/fcl-base/src/inifiles.pp` —
`TCustomIniFile` (:159–218), `TIniFile = class(TCustomIniFile)` (:222–259),
`TMemIniFile = class(TIniFile)` (:261–269), `TIniFileOption` (:143–152),
format constants (:279–283: `Brackets '[' ']' / Separator '=' / Comment ';' /
LF_Escape '\'`), `CharToBool` (:285). FPC fpcunit seed:
`packages/fcl-base/tests/utcinifile.pp` (2 Bool tests, mined verbatim in
`tests/005_FpcBoolParity.sh`). The file-format semantics come from the FPC
READER `TIniFile.FillSectionList` (:1033), not from INI folklore.

## Class hierarchy mapping

```
FPC:   TCustomIniFile (abstract)  <-  TIniFile  <-  TMemIniFile
bash:  TIniFile (folds Custom)    <-------------    TMemIniFile
```

`TCustomIniFile` is abstract in FPC (its `ReadString`/`WriteString`/
`ReadSection*` are `virtual; abstract`, implemented in `TIniFile`). A bash
abstract class is pure dispatch tax, so its concrete surface is FOLDED into
`TIniFile`; `TMemIniFile : TIniFile` keeps the real inheritance edge (the
third kcl consumer of kklass inheritance after tstringlist/tdictionary).

An object handle is a live kklass instance; a `TObject` value in FPC has no
analog here — INI stores only strings.

## Constructors / lifetime

| FPC | bash |
|---|---|
| `Create(AFileName, AOptions=[])` (:967, virtual) | `TIniFile.new ini <path> [tokens…]` — AUTO-adds `ifoStripQuotes` unless the instance is a TMemIniFile (`if not (self is TMemIniFile)`, :969); `CacheUpdates=false`; then `ReadIniValues`. |
| `TMemIniFile.Create` (:1447) | `TMemIniFile.new ini <path> [tokens…]` — `inherited` (no auto-quote add, the parent checks the class), then `CacheUpdates:=True`. |
| `Destroy` (:1024) | `ini.delete` — if `Dirty and CacheUpdates`, flush (errors EATEN, D7 compat, bug 19046), then kklass tears the instance down. |
| overloads with `TStream`/`TEncoding`/`AEscapeLineFeeds` | **wontfix** (no streams/encodings in bash); the `AEscapeLineFeeds` boolean maps to the `ifoEscapeLineFeeds` token. |

## Read members

| FPC | bash | Notes |
|---|---|---|
| `ReadString(Section,Ident,Default)` (:1125) | `ini.ReadString sec id default` → RESULT | first-match; StripQuotes at read |
| `ReadInteger`/`ReadInt64` (:690/:701) | same | `StrToIntDef`/`val()` grammar; here Int64==Integer (64-bit, no 32-bit clamp) |
| `ReadBool(...)` (:720) | `ini.ReadBool sec id default(0\|1)` → RESULT 0/1 | cascade: BoolStrings (CompareText, case-insensitive) → `ifoWriteStringBoolean`/SameText → `CharToBool` (first char `'1'`) |
| `ReadFloat` (:794) | same | **string-preserving** — no `StrToFloatDef` Double round-trip (divergence) |
| `SectionExists`/`ValueExists` (:680/:844) | same → rc 0/1 | |
| `ReadSection(Strings)` (:1200) | `ini.ReadSection sec arr` → RESULT=count | idents in order, comments excluded, `''` for invalid rows |
| `ReadSections(Strings)` (:1240) | `ini.ReadSections arr` | section names, comment-sections excluded, `''` for `[]` |
| `ReadSectionValues(...)` (:1255) | `ini.ReadSectionValues sec arr [svo…]` | `Ident=Value`; svoIncludeComments/Invalid/Quotes tokens; default = `[svoIncludeInvalid]` |
| `ReadSectionRaw` (:1218) | `ini.ReadSectionRaw sec arr` | `Ident=Value` for any non-empty ident (comment rows emit `;text=` — FPC quirk kept verbatim) |
| `ReadDate/DateTime/Time/BinaryStream` | — | **wontfix** (dateutils bridge possible later; streams impossible) |

## Write members

| FPC | bash | Notes |
|---|---|---|
| `WriteString(Section,Ident,Value)` (:1174) | `ini.WriteString sec id value` | first-match in-place (original ident case kept) or append; missing section appended; then MaybeUpdate. **Validation** rejects empty/`;`-leading/`=`-in-ident/CRLF (rc 1) |
| `WriteInteger`/`WriteInt64` (:696/:707) | same | `IntToStr` → canonical decimal |
| `WriteBool` (:746) | `ini.WriteBool sec id value` | `1`/`0`, or `BoolTrueStrings[0]`//`true` / `BoolFalseStrings[0]`//`false` under `ifoWriteStringBoolean` |
| `WriteFloat` (:828) | same | string-preserving (stores the literal) |
| `DeleteKey`/`EraseSection` (:1331/:1318) | same | silent on miss; flush only on an actual removal |
| `UpdateFile` (:1349) | `ini.UpdateFile` | compose → ForceDirectories → tmp+mv → re-parse + `Dirty:=false`; failure rc 1, memory kept |
| `SetBoolStringValues(bool,Values)` (:654) | `ini.SetBoolStringValues true\|false v…` | replaces a bool-strings list |
| `Options` property (:210) | `ini.options` var (space-joined tokens) | |
| `FileName` property | `ini.file_name` var | |

## TMemIniFile-only

| FPC | bash | Notes |
|---|---|---|
| `Clear` (:1460) | `ini.Clear` | empties the section list; `Dirty` untouched |
| `GetStrings(List)` (:1465) | `ini.GetStrings arr` → count | composed lines, blank after EVERY section (differs from UpdateFile by that one detail) |
| `SetStrings(List)` (:1502) | `ini.SetStrings arr` | replace content via re-parse; `Dirty` untouched |
| `Rename(AFileName,Reload)` (:1494) | `ini.Rename newName [true\|false]` | set file_name; if Reload, re-read from the new file (missing → empty) |

## Options (`TIniFileOption`, :143)

`ifoStripComments`, `ifoStripInvalid`, `ifoEscapeLineFeeds`,
`ifoCaseSensitive`, `ifoStripQuotes`, `ifoStringBoolean` (`=
ifoWriteStringBoolean`, alias :272) are supported. `ifoFormatSettingsActive`
follows the date family → **wontfix**.

## Deltas summary (bash-side; all tested)

| Topic | FPC | here |
|---|---|---|
| ReadFloat/WriteFloat | Double round-trip (canonicalizes) | string-preserving literal |
| ReadInteger width | 32-bit Longint | 64-bit, no clamp |
| eager-write failure | raises `EInOutError` | rc 1, memory kept |
| corrupting names/values (empty, `;`, `=`-in-ident, CRLF) | written, misread later | rejected rc 1 |
| line endings / BOM-write / encodings | platform / supported | LF only / wontfix |
| date-time, binary streams | supported | wontfix |
