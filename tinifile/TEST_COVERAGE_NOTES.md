# tinifile — test coverage notes

**Status: extended at kcl P8 (2026-09-08) by the 2026-09-06 review.** Suite
001-012 = 191 cases, green on bash 5.2.37 AND true 5.3.9 (was 84 at P4, 91
after kcl P1 added 006_Contract.sh).

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
| 002.utf8-fold | ReadString | ASCII case AND the accent fold, section and ident (was an accept-either observation; D6 makes UTF-8 part of the contract) | format | D6 / `` |
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

## 007 — persistence edges (kcl P8; review findings T1, T5, T7, T8, T12)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 007.dir-eager | WriteString | eager write onto a DIRECTORY → rc 1, memory kept, dir untouched | persist | T1 / FPC :1358 SaveToFile raises before FillSectionList+FDirty:=false |
| 007.dir-cached | UpdateFile | cached flush onto a DIRECTORY → rc 1, `dirty` STAYS true | persist | T1 |
| 007.dash | WriteString | relative name `-x.ini` is a NAME: written and read back | persist | T7 / `mv --` |
| 007.tmp-printf | UpdateFile | printf into the temp file fails → rc 1 and NO temp left (printf shadowed for one call) | persist | T7 (the branch the P1 `--` sweep did not touch) |
| 007.tmp-mv | UpdateFile | `mv` fails → rc 1, no temp left, `dirty` kept (mv shadowed) | persist | T7 |
| 007.readonly | WriteString | 0444 target → rc 1, content AND mode intact, memory holds the new value | persist | T8 / FPC SaveToFile |
| 007.eager-rc | DeleteKey/EraseSection | failed eager flush → rc 1 from both | persist | T5 / FPC :1313, :1300 propagate the exception |
| 007.eager-miss | DeleteKey/EraseSection | a MISS stays rc 0 even when a flush would fail | persist | S7 |
| 007.eager-ok | DeleteKey/EraseSection | a successful eager removal stays rc 0 and flushes | persist | S7 |
| 007.bs-write | UpdateFile | `\`-separated path: directory created, file written, stderr empty | persist | T12 / D5 |
| 007.bs-load | Create | the same `\`-path LOADS back | persist | T12 |
| 007.bs-var | file_name | the variable keeps the caller's text verbatim | contract | T12 |
| 007.no-tmp | — | no `*.tmp.*` survives anywhere under the fixture tree | persist | T7 |

## 008 — round-trip corruptions + SectionExists (kcl P8; T2, T3, T4)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 008.pair-reject | WriteString | ident `[list` + value `1,2]` → rc 1, section untouched | format | T2 / reader :1069 |
| 008.pair-ok | WriteString | the same ident with `1,2` (no `]`) is ACCEPTED and round-trips | format | T2 (the rule is the composed LINE, not the ident) |
| 008.pair-nosec | ReadSections | no bogus section was created | format | T2 |
| 008.brackets-ok | WriteString | ident `x]`/`[x]` with a `]`-value still legal | format | T2 |
| 008.semi-sec | UpdateFile | `[;x]` keeps its brackets and its keys | format | T3 / composer :1341 vs reader :1072 |
| 008.semi-idem | UpdateFile | idempotent across two flushes and a reopen; `;x` still unlisted | format | T3 |
| 008.semi-addr | SectionExists/ReadString | `[;x]` is NOT addressable, as FPC SectionByName | format | T3 / :526 |
| 008.comment-sec | UpdateFile | a REAL comment-section still composes without brackets | format | T3 |
| 008.adopt | UpdateFile | a leading comment ADOPTS the keys that follow it | format | FPC :1059-1066 assigns oSection (beyond the review list) |
| 008.adopt-strip | UpdateFile | with ifoStripComments no section is made, so the key IS dropped | format | FPC :1061 |
| 008.exists | SectionExists | empty=no, comment-only=no, invalid-row=YES, full=yes, absent=no | format | T4 / :670 + :483 |
| 008.exists-result | SectionExists | RESULT mirrors the rc on both branches | contract | T4 |
| 008.exists-listed | ReadSections/ValueExists | the sections are still listed and readable | format | T4 |
| 008.exists-delete | WriteString+DeleteKey | absent → exists → empty-so-not-exists, still listed | format | T4 |
| 008.exists-comment | SectionExists/ValueExists | a comment key is not a key | format | T4 / KeyByName :450 |
| 008.dup-erase | EraseSection | duplicate sections: the FIRST is erased, the second survives | format | FPC first-match (test gap named by the review) |

## 009 — escape-line-feeds + the val() grammar (kcl P8; T9, T10, T11)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 009.last-bs | ReadString | trailing `\` on the LAST line is kept | format | T9 / RemoveBackslashes :1030 `Count-2 downto 0` |
| 009.last-bs-nonl | ReadString | same with no final newline | format | T9 |
| 009.last-bs2 | ReadString | a DOUBLE backslash on the last line keeps both | format | T9 |
| 009.last-bs-bare | ReadSectionRaw | a bare `\` last line stays an invalid row | format | T9 |
| 009.mid-bs | ReadString | a middle `\` still joins; an open chain keeps its final `\` | format | T9 |
| 009.empty-join | ReadString | an empty line after a `\` line joins to nothing | format | T9 / `AStrings.Delete(I+1)` |
| 009.write-bs | WriteString | value ending in `\` under the option → rc 1, next key intact | format | T10 |
| 009.write-bs-mid | WriteString | an interior backslash is fine | format | T10 |
| 009.write-bs-noopt | WriteString | without the option the same value round-trips | format | T10 |
| 009.write-bs-names | WriteString | a section/ident ending in `\` stays legal (not at end of line) | format | T10 |
| 009.int-* (34 rows) | ReadInteger | the whole InitVal grammar: blanks, TAB, sign, `$`/`x`/`X`/`0x`/`&`/`%`, leading zeros, trailing blank, the int64 and ValUInt boundaries, overflow→Default | typed | T11 / sstrings.inc :1086 + :1141 |
| 009.int64 | ReadInt64 | same grammar on the Int64 entry point | typed | T11 |
| 009.write-int | WriteInteger | canonicalises `' x1F'`→31; refuses overflow, stores nothing | typed | T11 |
| 009.quoted | ReadInteger | quoted numbers still go through StripQuotes | typed | T11 |

## 010 — output/input array names (kcl P8; T13)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 010.sweep (6 rows) | ReadSection, ReadSections, ReadSectionValues, ReadSectionRaw, GetStrings, SetStrings | 21 malformed/reserved names each → rc 2, silent, instance intact | contract | T13 / kcl README §1.7 + owner decision 2026-09-07 (rc 2) |
| 010.instance-var | ReadSections | a caller array named `dirty` is refused, both it and the flag intact | contract | T13 |
| 010.assoc | ReadSections | an associative target is refused | contract | T13 / same rule as thashset |
| 010.good | all six | valid names still fill correctly | contract | regression guard |
| 010.result | ReadSection | RESULT = count on success, empty after rc 2 | contract | kcl README §1.2 |
| 010.setu | ReadSections | the refusal is clean under `set -eu` | contract | D7 |

Each sweep runs in a CHILD shell on purpose: before the fix a name like `IFS`
or `this` did not merely misbehave, it corrupted the shell that made the call,
and a corrupted runner cannot report anything (the first draft of this file
reported "0 tests" instead of failing).

## 011 — cost shape (kcl P8; T6)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 011.append | WriteString | 800 cached appends < 10× 200 appends | perf | T6, relative gate per PLAN §4 |
| 011.structural | `_findKey` | the body calls no helper per row and iterates no whole-table index | perf | T6 |
| 011.position | ReadString | a lookup in section 20 < 3× one in section 1 | perf | T6 |
| 011.values | ReadString | the faster lookup still returns first/last/miss correctly | format | T6 regression guard |
| 011.holes | DeleteKey+WriteString | appends after a deletion land in the right section | contract | the new next-free-row counter |
| 011.erase | EraseSection+WriteString | compose and lookups agree after an erase | contract | the new per-section row list |
| 011.bulk | UpdateFile+Create | an 800-key instance composes and reloads intact | persist | T6 |

## 012 — locale self-heal (kcl P8; D6)

| ID | Members | Case | Class | Basis |
|---|---|---|---|---|
| 012.export | source | a bare environment (LC_ALL, LC_CTYPE and LANG all cleared) gets LC_CTYPE=C.UTF-8 at load | contract | D6 / kcl README §1.6 |
| 012.fold-section | ReadString | the accent folds in a bare environment (section name) | format | D6 |
| 012.fold-ident | ReadString | ... and in the ident | format | D6 |
| 012.lossless | WriteString/UpdateFile/ReadString | a non-ASCII value still round-trips byte-exact through a file | format | UTF-8 audit |
| 012.explicit | source | an EXPLICIT locale (LC_ALL=C) is never overridden | contract | D6 |
| 012.ascii | ReadString | ASCII folding works whatever the locale | format | §2.3 |

Every case runs in a CHILD bash with the three variables cleared: the runner
has already pinned LC_ALL=C.UTF-8 in this process, so the load-time behaviour
is invisible from here.

## Deliberately NOT covered (documented elsewhere)

- Date/time, binary streams, encodings, BOM-write — wontfix (ledger
  out_of_scope; README/docs deltas).
- 32-bit Longint overflow — documented divergence (Integer == Int64 here, no
  clamp). The >63-bit *wrap* is no longer an edge: since P8 an out-of-range
  literal is a conversion error and returns the Default, exactly as FPC's
  `Code<>0` does, and both boundaries are pinned in 009.
- Non-ASCII case folding is now PINNED, not observed: D6 makes a UTF-8 locale
  part of the contract, the unit self-heals a bare environment at load time and
  012 proves it in a child shell. What stays out of scope is folding under a
  deliberately non-UTF-8 locale, which is the caller's choice (012.explicit).
- Performance thresholds — still **no hard-ms asserts** (flake-prone under
  sweep load, house lesson). 011 and `bench.sh` gate the *ratios* instead:
  800 appends against 200, and a lookup in the 20th section against the 1st.
