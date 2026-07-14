# tinifile — test coverage notes

**Status: FINALIZED at P4 (2026-07-14).** Suite 001–005 = 84 cases, green on
bash 5.2.37 AND true 5.3.9.

Protocol (house): **invented** cases get a row here; **FPC-traceable** cases
(005_FpcBoolParity.sh — the complete fpcunit suite
`packages/fcl-base/tests/utcinifile.pp`, mined verbatim) cite their FPC
procedure + seed line instead. The format spec itself is the FPC READER
(`FillSectionList`), so most "invented" rows are really SOURCE-PINNED against
`inifiles.pp` — the S-column cites the PLAN.md §3 pin (which carries the
line anchor). Classes: `contract` (rc/RESULT/validation/zero-fork), `format`
(reader/writer semantics), `persist` (eager/cached/round-trip), `typed`
(conversions).

## 001 — skeleton / ctor core (P0)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 001.eager | Create | TIniFile: eager + AUTO ifoStripQuotes | contract | S8 / FPC :967 |
| 001.cached | Create | TMemIniFile: cached + NO auto-quotes | contract | S10 / FPC :969 |
| 001.tokens | Create | tokens parsed/deduped; alias ifoWriteStringBoolean→ifoStringBoolean | contract | :272 |
| 001.optin | Create | TMemIniFile explicit ifoStripQuotes kept | contract | token grammar |
| 001.bogus | Create | unknown token → rc 1, instance valid | contract | house token convention |
| 001.storage | Create | secnames/kident/kvalue/kowner exist, empty | contract | storage freeze §2.2 |
| 001.inherit | — | M is TMemIniFile, parent chain → TIniFile | contract | kklass inheritance |
| 001.typed-default | ReadInteger/ReadBool | empty ini → defaults, rc 0 | contract | default-based API |
| 001.teardown | delete | storage arrays unset | contract | dtor |
| 001.resource | — | re-source is a clean no-op | contract | guard |
| 001.zero-fork | Create/delete | ctor/dtor + read under PATH='' | contract | builtins only |

## 002 — load + read core (P1)

| ID | Members | Case | Class | Basis (PLAN §3 pin) |
|---|---|---|---|---|
| 002.trim | ReadString | line/ident/value trimmed; CRLF stripped | format | S8 |
| 002.eqvalue | ReadString | value keeps `=` and `;` | format | S12 |
| 002.quotes | ReadString | TIniFile strips quotes at read | format | S8 |
| 002.orphan | SectionExists/ReadString | key before any section dropped | format | S4 |
| 002.dupsec | ReadString | duplicate section — first wins | format | S3 |
| 002.dupkey | ReadString | duplicate key — first wins; case-insensitive | format | S3 |
| 002.rbracket | ReadString | `]` legal inside a name | format | S4 |
| 002.nonl | ReadString | no-final-newline line kept | format | file I/O §2.4 |
| 002.emptyvsabsent | ReadString | empty value ≠ absent key | contract | trap #6 |
| 002.empty-sec | ReadSections/ReadString | `[]` listed as `''` but unaddressable | format | S4 |
| 002.readsection | ReadSection | idents in order, comments out, `''` for invalid | format | S12 / :1211 |
| 002.rsv-default | ReadSectionValues | default (invalid in, comments out, quotes stripped) | format | :1255 |
| 002.rsv-flags | ReadSectionValues | +comments +quotes tokens | format | :1264 |
| 002.raw | ReadSectionRaw | `Ident=Value` + `;comment=` quirk verbatim | format | :1218 |
| 002.exists | SectionExists/ValueExists | hits/misses/case-insensitive | contract | :680/:844 |
| 002.mem-quotes | ReadString | TMemIniFile keeps quotes | format | S8 |
| 002.casesens | ReadString | ifoCaseSensitive exact-only; dup-key second | format | S3/§2.3 |
| 002.strip | ReadSection/ReadSections | StripComments+StripInvalid at load | format | S2 |
| 002.escape | ReadString | ifoEscapeLineFeeds join vs literal | format | §1.5 / :1039 |
| 002.missing | Create/SectionExists | missing file → empty, rc 0 | contract | S1 |
| 002.utf8-exact | ReadString/SectionExists | exact-case unicode names + lossless cyrillic value | format | UTF-8 audit |
| 002.utf8-fill | ReadSection | unicode idents lossless in fills | format | UTF-8 audit |
| 002.utf8-fold | ReadString | ASCII-fold deterministic; É-fold = locale observation | format | `${x,,}` house pin |
| 002.zero-fork | read family | parse + all reads under PATH='' | contract | builtins only |

## 003 — write core + persistence (P2)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 003.eager | WriteString | TIniFile hits disk immediately | persist | S10 |
| 003.cached | WriteString/UpdateFile | dirty until UpdateFile, then clean | persist | S10 |
| 003.destroy-flush | Destroy | dirty+cached saves; clean does not | persist | :1024 |
| 003.inplace | WriteString/GetStrings | first-match, position + original ident case | format | :1174 |
| 003.compose | UpdateFile | comments verbatim, blank rule, `=value` quirk; idempotent | format | :1358 |
| 003.silentmiss | DeleteKey/EraseSection | silent on miss; erase kills comments | format | S7 |
| 003.getstrings | GetStrings | blank line after EVERY section | format | :1486 |
| 003.setstrings | SetStrings | closure; dirty untouched | persist | :1502 |
| 003.clear | Clear | content gone, dirty untouched | persist | :1460 |
| 003.rename | Rename | false keeps memory; true reloads | persist | S11 |
| 003.mkdir | UpdateFile | creates missing directories | contract | S9 |
| 003.unwritable | UpdateFile | rc 1, memory kept, dirty stays | contract | §2.7 |
| 003.validate | WriteString | empty/`;`/`=`-in-ident/CRLF → rc 1, no dirty | contract | §2.7 |
| 003.utf8-disk | WriteString/UpdateFile | UTF-8 write→read round-trip through a file | format | UTF-8 audit |
| 003.zero-fork | write family | in-memory writes under PATH='' | contract | builtins only |

## 004 — typed accessors (P3)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 004.int-forms | ReadInteger | decimal/`$hex`/`0x`/`&oct`/`%bin` | typed | S5 |
| 004.int-sign | ReadInteger | sign + leading-zero-is-DECIMAL | typed | S5 |
| 004.int-invalid | ReadInteger | invalid/absent → default | typed | S5 |
| 004.int64 | ReadInt64/ReadInteger | 64-bit, no 32-bit clamp | typed | §1 note |
| 004.int-write | WriteInteger | canonical decimal; reject non-int | typed | :696 |
| 004.bool-firstchar | ReadBool | default cascade — first char `'1'` | typed | S6 / :285 |
| 004.bool-empty | ReadBool | empty + absent → default | typed | S6 |
| 004.bool-string | ReadBool | ifoStringBoolean case-insensitive true/false | typed | S6 |
| 004.bool-list | ReadBool | BoolStrings case-insensitive membership | typed | S6 / :716 |
| 004.bool-write | WriteBool | `1`/`0` default; reject non-bool | typed | :746 |
| 004.bool-write-str | WriteBool | ifoStringBoolean → `true`/`false` then BoolStrings[0] | typed | :746 |
| 004.float-preserve | ReadFloat | preserves the LITERAL (no canonicalization) | typed | §2.6 |
| 004.float-reject | ReadFloat/WriteFloat | non-floats → default / rc 1 | typed | §2.6 |
| 004.typed-quotes | ReadInteger/ReadFloat | typed reads inherit StripQuotes | typed | :690 via :1136 |
| 004.zero-fork | typed family | typed read/write under PATH='' | contract | builtins only |

## 005 — FPC Bool parity (FPC-TRACEABLE; utcinifile.pp)

The complete fpcunit seed, 16 assertions, each citing its seed line. Adapted:
`TMemIniFile.Create('tmp.ini')` (fresh per FPC Setup) → a fresh cached
instance per FPC procedure; `Options := Options + [ifoWriteStringBoolean]` →
appending `ifoStringBoolean` to the `options` var; `ReadBool` Boolean default →
`0`/`1`.

| ID | Members | Case | Basis (FPC proc / seed line) |
|---|---|---|---|
| 005.wb-true | WriteBool/ReadString | default true → `'1'` | TestWriteBoolean :50 |
| 005.wb-false | WriteBool/ReadString | default false → `'0'` | :52 |
| 005.wb-strue | WriteBool/ReadString | ifoStringBoolean true → `'true'` | :55 |
| 005.wb-sfalse | WriteBool/ReadString | ifoStringBoolean false → `'false'` | :57 |
| 005.wb-arr-t | WriteBool/SetBoolStringValues | BoolTrueStrings[0] → `'t'` | :60 |
| 005.wb-arr-f | WriteBool/SetBoolStringValues | BoolFalseStrings[0] → `'f'` | :63 |
| 005.rb-1 | ReadBool | `'1'` → true | TestReadBoolean :73 |
| 005.rb-0 | ReadBool | `'0'` → false | :75 |
| 005.rb-empty | ReadBool | empty → Default | :77 |
| 005.rb-first | ReadBool | first list match `'t'` → true | :80 |
| 005.rb-second | ReadBool | second list match `'true'` → true | :82 |
| 005.rb-nomatch | ReadBool | no match → Default | :84 |
| 005.rb-f-first | ReadBool | first false match `'f'` → false | :88 |
| 005.rb-f-second | ReadBool | second false match `'false'` → false | :90 |
| 005.rb-both | ReadBool | both lists set, no match → Default | :94 |
| 005.rb-sbool | ReadBool | ifoStringBoolean true/false/no-match | :99/:101/:103 |

## Deliberately NOT covered (documented elsewhere)

- Date/time, binary streams, encodings, BOM-write — wontfix (ledger
  out_of_scope; README/docs deltas).
- 32-bit Longint overflow / >63-bit integer wrap — documented divergence (no
  clamp; bash-wrap edge noted in `_toInt`).
- Non-ASCII case folding beyond the observation row — locale-dependent by
  design (`${x,,}` house pin; PLAN §2.3).
- Performance thresholds — no hard-ms asserts (flake-prone under sweep load,
  house lesson); `bench.sh` reports honest numbers instead.
