# fpjson (TJSONData / TJSONObject / TJSONArray) → bash port plan (kcl/fpjson)

**Roadmap position:** 7/7 (owner priority order, 2026-07-12) — the strategic epic of the roadmap.

**Status:** **P0 re-planned 2026-09-09** by kcl `PLAN.md` phase **P10** under owner decision
**D8**. The two architecture forks the previous draft reserved for an owner review are
**closed**: node model = **(B) document instance + integer handles**; engine = **pure bash,
windowed lexer**, with the awk co-process left as the optional last phase. The DRAFT flag is
gone. Everything below is written against measurements taken on this machine (§4.1, §4.2,
§3.4) — no design claim in this plan is unmeasured.

**Source of truth:** FPC 3.2.2, GitLab mirror, tag `release_3_2_2`, template
`https://gitlab.com/freepascal.org/fpc/source/-/raw/release_3_2_2/<path>`:

| file | lines | role |
|---|---|---|
| `packages/fcl-json/src/fpjson.pp` | 4108 | data model, serialisation, FindPath |
| `packages/fcl-json/src/jsonscanner.pp` | 616 | lexer, `TJSONOptions` |
| `packages/fcl-json/src/jsonparser.pp` | 275 | parser (stack machine) |
| `packages/fcl-json/src/jsonreader.pp` | 631 | structural reader used by the parser |

> The previous draft cited 4322 / 758 / 290 lines. Those numbers are **not** the
> `release_3_2_2` files (they are trunk); every line reference in this plan was re-read from
> the tag above and is quoted in the form `fpjson.pp:NNN`.

**Target:** `kcl/fpjson/fpjson.sh` — one kklass **instantiable** class `TJSONData` per
document; nodes are integer handles (§3).
**Ledger:** `kcl/fpjson/fpjson_ledger.json`.
**Contract:** `kcl/README.md` §1 in full, from the first line of code (§9) — this unit is the
first one written *after* the contract instead of retrofitted into it.
**Workflow:** phase → dual-bash tests → full master sweep → STOP → "go"; commits gated; no
unit edits during a sweep.
**Conventions:** as `kcl/tdictionary/PLAN.md` §2.2–2.4/§6.

---

## 0. What P10 changed, and why

The 2026-09-06 review (`docs/review-2026-09-06/08_cross_cutting_and_fpjson.md`, Task 5)
measured the draft's central assumption and found it wrong:

* the draft's lexer idiom — `${s:i:1}` over the whole document under `LC_ALL=C` — is **O(n²)**,
  because indexing a *large* string is O(n) per access. Re-measured here (§4.1): **96 KB =
  38.7 s** on 5.2.37. A 100 KB payload would not have landed "in whole seconds"; it would have
  landed in most of a minute.
* the same scan over a small **window** sliced out of the document is **20×** faster, and a
  window + first-byte dispatch + regex for strings/numbers (§4.1) does 96 KB in **1.6 s** and
  20 KB in **0.29 s** — inside the P0 gate with 3–4× headroom.

Everything else in this rewrite follows from designing against the kcl contract and from
re-reading the FPC sources at the release tag rather than from memory:

1. `_parent[id]` added (Delete/Remove/Clone/serialise need it) — was missing.
2. `_kids[id]` is a **space-separated list of integer ids**, not an `\x1f`-joined scalar; member
   **names** are stored per *child id*, never joined (JSON names may contain any character,
   `\x1f` included).
3. The destructor's reserved-suffix list is enumerated and asserted by a test (§3.5), with a
   measured teardown target (§3.4).
4. Duplicate-key policy pinned on **parse** and on **Add** from the real FPC code (§5.3).
5. FindPath grammar pinned from the three `DoFindPath` implementations, including the fact that
   FPC **cannot address a member whose name contains `.` or `[`** (§6).
6. `\uXXXX` decoding: `printf '\uXXXX'` is **unusable** inside the lexer — measured (§4.2) —
   so UTF-8 is composed by hand, surrogate pairs included.
7. Error contract aligned with **D2** (rc 1 + `RESULT=""` + `kk.debug`), with the positioned
   message reachable as data through `doc.LastError` (§5.5).
8. A max-depth guard: FPC has **none** (grep for `Nesting`/`Depth` over all four units returns
   nothing) — ours is a documented addition (§5.4).
9. Numbers stay literals, and the number edge cases the review named (`-0`, `1E400`, int64
   boundaries) are pinned as tests (§4.5).

---

## 1. Scope (from the original draft)

*These are the owner's scope statements from the 2026-07-12 draft, kept verbatim in substance.*

Why port at all: kkbot lives among JSON-speaking APIs, and today every touch is a `jq`
fork. A native parser/serializer makes small-payload JSON (configs, API responses,
state files) zero-fork and lossless within bash string limits. Honest positioning:
**configs and API payloads, not log streams** — bench publishes real numbers (§11).

### 1.1 Ported (v1 target surface)

| FPC | bash | Notes |
|---|---|---|
| `GetJSON(text)` (parse) | `TJSONData.new doc` + `doc.Parse text` (and `doc.ParseFile path`) | error → rc 1 + `RESULT=""`, message with **line:col** via `doc.LastError` (§5.5) |
| `TJSONData.JSONType` | `doc.TypeOf node` → `jtObject`/`jtArray`/`jtString`/`jtNumber`/`jtBoolean`/`jtNull` | node = integer handle (§3) |
| `AsJSON` (compact) | `doc.AsJSON [node]` | byte-parity with FPC, including its spaces (§7.1) |
| `FormatJSON` (pretty) | `doc.FormatJSON [node] [options] [indent]` | the six `TFormatOption`s (§7.2) |
| `FindPath(APath)` / `GetPath` | `doc.FindPath node path` / `doc.GetPath node path` | FPC grammar exactly, dots and `[n]` (§6) |
| `AsString/AsInteger/AsInt64/AsBoolean/AsFloat/IsNull` | `doc.AsString node` … | numbers STRING-PRESERVING (§4.5); `AsFloat` = validated passthrough |
| `Count`, `Items[i]`, `Names[i]`, `Elements[name]` | `doc.Count node`, `doc.Item node i`, `doc.Name node i`, `doc.Element node name` | object key order = INSERTION order (`TFPHashObjectList`, `fpjson.pp:606`) |
| `TJSONObject.Add(name, …)` typed family | `doc.ObjAdd node name type value` | duplicate = error, per FPC (§5.3) |
| `TJSONArray.Add(…)` family | `doc.ArrAdd node type value` | |
| `Delete(index/name)`, `Remove`, `Clear`, `Extract` | `doc.ObjDelete/ArrDelete/Remove/Clear/Extract` | |
| `Clone` | `doc.Clone node [destDoc]` | deep copy |
| iteration | `doc.ForEach node cb`, `doc.Items node OUT`, `doc.Names node OUT` | cb `<doc> <node> <index-or-name> <childHandle>`; snapshot semantics |
| string escapes | full RFC: `\" \\ \/ \b \f \n \r \t \uXXXX` incl. surrogate pairs | `\u0000` follows FPC and is dropped (§4.4) |

### 1.2 NOT ported (wontfix)

1. **The five number classes** (`TJSONFloatNumber`/`TJSONIntegerNumber`/`TJSONInt64Number`/
   `TJSONNativeIntNumber`/`TJSONQWordNumber`, `fpjson.pp:182–393`) — bash keeps ONE number kind
   with the LITERAL preserved plus an int/float subtype tag. No Double roundtrip, no precision
   loss, no float-engine dependency (kcl/math exists for arithmetic). The no-parity-theater rule.
2. **TStream/reader/writer integration** (`jsonreader.pp`, `jsonwriter.pp`, stream parse) — no
   streams in bash; `ParseFile` reads whole files (§8).
3. **fpjsonrtti / jsonconf / json2yaml / fpjsonvalue helpers** — separate FPC units, out of scope.
4. **UnicodeString/`TJSONUnicodeStringType` distinctions** (`fpjson.pp:51`) — bash strings are
   UTF-8 bytes; one string kind.
5. **Enumerator objects** (`TBaseJSONEnumerator`, `fpjson.pp:99–104`) — `ForEach` instead.
6. **CompareJSON / jsoncomparer** — possible later extra, not v1.
7. **NUL bytes** — bash language limit; a file containing one is rejected by `ParseFile` (§8),
   and `\u0000` inside a string follows FPC and vanishes (§4.4).
8. **`Variant` access** (`GetValue`/`SetValue`, `fpjson.pp:142–143`) — no variants in bash;
   `AsString`/`AsInteger`/… cover it.
9. **`TJSONObject`'s 255-character name limit** (`fpjson.pp:606`, "Careful : Names limited to
   255 chars." — a `TFPHashObjectList` artefact). We have no such limit and do not fake one.
10. **`Sort`** (`fpjson.pp:578`, `TListSortCompare`) — a Pascal callback type; a bash sort of an
    array node is a later extra, not v1.

---

## 2. Pinned FPC semantics (S1–S12 — the table the draft left open)

Every row was read at the tag; the "answer" column is what the port implements unless the
"port" column says otherwise.

| # | Question | FPC answer (anchor) | Port |
|---|---|---|---|
| **S1** | Duplicate object keys — on `Add` and on parse | `TJSONObject.DoAdd` (`fpjson.pp:3725-3741`) raises `EJSON` `'Duplicate object member: "%s"'` (`:822`) when `IndexOfName(aName)<>-1`. The parser (`jsonparser.pp:126-150`) lets that exception out **unless** `joIgnoreDuplicates` is set, in which case the later value is freed and the **first wins** | same, with rc 1 instead of an exception (§5.3) |
| **S2** | Object member order | insertion order — storage is `TFPHashObjectList` (`fpjson.pp:606`), `Names[i]`/`Items[i]` walk it by index (`:3287`) | same (`_kids` is an ordered id list) |
| **S3** | `AsJSON` exact bytes | class vars decide: `ElementSeps=(', ', ',')` (`:111`), `ObjStartSeps=('{ ','{')`, `ObjEndSeps=(' }','}')`, `ElementStart=('"','')`, `SpacedQuoted=('" : ',' : ')`, `UnSpacedQuoted=('":',':')` (`:606-611`), selected by `CompressedJSON` (`:1471`) and `UnquotedMemberNames` (`:3256`). Default (both false): `{ "a" : 1, "b" : 2 }`, `[1, 2]`; empty containers are `{}` / `[]` (`:3437`, `:2620`) | byte-identical (§7.1) |
| **S4** | `FormatJSON` options and indent | `TFormatOption = (foSingleLineArray, foSingleLineObject, foDoNotQuoteMembers, foUseTabchar, foSkipWhiteSpace, foSkipWhiteSpaceOnlyLeading)` (`:64-70`); `DefaultIndentSize=2`, `DefaultFormat=[]` (`:74-75`); impls `:2632` (array) and `:3592` (object) | all six (§7.2); `sLineBreak` = LF, not CRLF (documented divergence) |
| **S5** | FindPath grammar | three impls: scalar `:1489` (any non-empty path → nil), object `:3276`, array `:2512` | reproduced exactly (§6) |
| **S6** | Scanner strictness | `TJSONOption = (joUTF8, joStrict, joComments, joIgnoreTrailingComma, joIgnoreDuplicates, joBOMCheck)` (`jsonscanner.pp:54`), `DefaultOptions=[joUTF8]` (`:57`). With `joStrict` OFF (the default!) FPC accepts single-quoted strings (`:317`), bare/`identifier` member names and case-insensitive `TRUE`/`Null` (`:569-580`), raw control characters inside strings (`:396`), leading zeros (`:423`), `.5` and `1.e5` (`:426`, `:440`). Trailing commas are rejected unless `joIgnoreTrailingComma` (`jsonreader.pp:372,400`) | options carry the FPC names; **default differs** — see §12 open question O1 |
| **S7** | Lone surrogates, bad `\u` | scanner (`jsonscanner.pp:342-370`): four hex digits required, else `SErrInvalidCharacter`; a pending `u1` is composed with the next `\u` **blindly** (no surrogate-range check) and `UTF8Encode`d; a pending single is flushed alone (CESU-8 bytes for a lone surrogate); **`\u0000` appends nothing and clears the pending slot** — it is silently dropped | same bytes (§4.4) |
| **S8** | Cross-type coercions | per class: `TJSONString.GetAsInteger = StrToInt` (raises on junk, `:1699`), `GetAsBoolean = StrToBool` (`:1594`), `GetAsFloat` = `Val` then `TryStrToFloat` else `EConvertError` (`:1605`); `TJSONBoolean.GetAsInteger = Ord` (`:1775`); array/object `AsString` etc. raise `ConvertError` (`:2545`, `:3443`) | conversions that raise in FPC = rc 1 + `RESULT=""` (D2) |
| **S9** | `Clone` | deep, per class (`TJSONArray.Clone :2401`, `TJSONObject.Clone :3196`); object clone re-`Add`s in index order, so names order is kept | same |
| **S10** | Number literal edges | scanner `:413-470`: sign, then `1-9` / `0` / `.`; `0` followed by a digit is an error **only** under `joStrict`; a fraction needs a digit after `.` unless `joStrict` is off and an `e` follows; an exponent **always** needs at least one digit; the token must end on `#13 #10 #0 } ] , TAB SPACE`, else `SErrInvalidCharacter` (`:464`); a leading `.` is rewritten to `0.` in the token text (`:470`) | RFC grammar by default (O1); the literal is kept byte-exact (§4.5) |
| **S11** | Nesting-depth guard | **none** anywhere in the four units | ours is an addition, default 512 (§5.4) |
| **S12** | null vs missing in FindPath | `FindPath` returns `nil` for a miss (`:1518`) and a real `TJSONNull` node for a present null; `GetPath` raises `SErrPathElementNotFound` `'Path "%s" invalid: element "%s" not found.'` (`:823`, `:1532`); `IsNull` is `False` on the base class (`:1500`) and `True` only on `TJSONNull` (`:1897`) | miss = rc 1 + `RESULT=""`; present null = rc 0, handle in `RESULT`, `doc.IsNull` true |

---

## 3. Node model (B) — document instance + integer handles

### 3.1 Why not an object per node

`TDictionary.new` costs ≈1.2 ms and a method call ≈0.47 ms on a loaded shell (review Task 5).
A 10 000-node document would be tens of seconds of constructors before a single byte is read.
Ten thousand nodes in parallel arrays cost **74–87 ms** (§3.4). Option (A) is rejected by
arithmetic, option (C) (path-only, re-resolve every access) by O(depth) per access.

### 3.2 Storage

One kklass instance per **document**. Nodes are integer ids into per-document global arrays
named from the instance (`kcl/README.md` §1.9 makes freeing them the unit's own job):

| array | kind | content |
|---|---|---|
| `${doc}_type[id]` | indexed | one byte: `o` object, `a` array, `s` string, `n` number, `b` boolean, `z` null |
| `${doc}_value[id]` | indexed | scalars only: decoded string bytes / number **literal** / `true`\|`false` / `""` for null |
| `${doc}_kids[id]` | indexed | **space-separated child ids**, `""` when empty — e.g. `"3 7 12"` |
| `${doc}_names[id]` | indexed | the member name **of this node inside its parent object**, indexed by the CHILD's id — never a joined list, so a name may contain any byte |
| `${doc}_parent[id]` | indexed | parent id; `0` for the root |
| `${doc}_index[key]` | associative | `"${parentId}:${name}" → childId` — O(1) `Element`/`Find` and O(1) duplicate detection. The key is unambiguous because the id is decimal digits up to the **first** `:` |

Scalars of the document itself live in kklass's own `state` (= `${doc}_data`, which kklass
creates and frees): `state[root]`, `state[nextid]`, `state[count]`, `state[opts]`,
`state[maxdepth]`, `state[err]`.

**Handles are monotonic and never reused.** `0` is "no node", so it can never collide with a
valid handle and the D2 miss contract (`rc 1` + `RESULT=""`) stays unambiguous. A free list was
considered and **rejected**: recycling an id makes a stale handle silently address a *different*
node, and bash gives us no cheap generation counter to catch it. The cost is that ids grow with
the number of nodes ever allocated in a mutation-heavy document; `doc.Clone` into a fresh
document compacts, and that is the documented remedy.

### 3.3 Names, not joins

The draft's `\x1f`-joined names are wrong: JSON member names may contain **any** Unicode
character, `U+001F` included. Storing the name in a slot keyed by the child's own id removes
the question. Child **ids** are integers, so joining *those* on a space is always safe, and
`kids` is read back with `read -ra` (fork-free) or iterated with `for k in ${kids}` under a
locally cleared `IFS`.

### 3.4 Teardown, measured

Measured on this machine (`scratchpad` probe, both bashes, 10 000 nodes):

| operation | 5.2.37 | 5.3.9 |
|---|---|---|
| build 10k nodes × 5 associative arrays | 78 ms | 74 ms |
| build 10k nodes × 5 indexed arrays | 87 ms | 87 ms |
| `unset -v` all six arrays | 8 ms | 4 ms |
| `unset -v` five indexed arrays | 2 ms | 2 ms |

**Target pinned for P6:** `doc.delete` of a 10 000-node document ≤ **50 ms** on both bashes
(≈6–25× headroom over the measurement), and *every* reserved suffix gone afterwards.

### 3.5 Destructor

The reserved suffixes are declared **once**, in one array in the source, and the destructor
unsets exactly that list:

```
__KK_FPJSON_SUFFIXES=(_type _value _kids _names _parent _index)
```

The contract test asserts, for every suffix, that `declare -p "${doc}${suffix}"` fails after
`doc.delete`, and that a **new** document created with the same instance name starts empty
(the pre-filled-storage bug `kcl/README.md` §1.9 warns about). `${doc}_data` and `${doc}_class`
remain kklass's business.

---

## 4. Lexer

### 4.1 Windowed, because whole-string indexing is O(n²)

`bench/lexer_probe.sh` (this phase's deliverable; run it, do not trust these numbers when the
machine changes). Window 2048 / refill < 256, `LC_ALL=C.UTF-8` ambient, documents 2081 / 20355 /
97385 bytes, 797 / 7637 / 36221 tokens, all four tokenizers agreeing on the token count:

| document | idiom | 5.2.37 | 5.3.9 |
|---|---|---|---|
| 2 KB | `bytes` — `${s:i:1}` over the whole document | 33 ms | 21 ms |
| | `winbytes` — same scan over a 2 KB window | 35 ms | 29 ms |
| | `regex` — one `[[ =~ ]]` per token, all kinds in one pattern | 35 ms | 38 ms |
| | **`hybrid`** — window + first-byte `case` + regex for strings/numbers | **29 ms** | **26 ms** |
| 20 KB | `bytes` | 1758 ms | 770 ms |
| | `winbytes` | 361 ms | 282 ms |
| | `regex` | 368 ms | 365 ms |
| | **`hybrid`** | **290 ms** | **251 ms** |
| 96 KB | `bytes` | **38 734 ms** | 15 327 ms |
| | `winbytes` | 1924 ms | 1397 ms |
| | `regex` | 1836 ms | 1870 ms |
| | **`hybrid`** | **1591 ms** | **1278 ms** |

**P0 gate: 20 KB ≤ 1 s on 5.2.37 — PASS at 290 ms** (the probe asserts it and exits non-zero if
it ever fails).

Window size sweep at 20 KB (`--sweep`), which is why the window is **not** 2 KB:

| window | regex 5.2 | hybrid 5.2 | winbytes 5.2 | regex 5.3 | hybrid 5.3 | winbytes 5.3 |
|---|---|---|---|---|---|---|
| 128 | 307 | 240 | 264 | 362 | 224 | 240 |
| **256** | 299 | **239** | 256 | 347 | **211** | 241 |
| 512 | 293 | 244 | 282 | 343 | 216 | 250 |
| 1024 | 313 | 273 | 319 | 357 | 229 | 255 |
| 2048 | 368 | 336 | 392 | 393 | 261 | 278 |
| 4096 | 471 | 447 | 539 | 443 | 325 | 353 |

Two findings that amend D8's letter and must be read together:

1. **The window is what buys the 5–24×, not the regex.** A plain character scan *inside a
   window* is as fast as the all-in-one regex (and faster on 5.3.9). D8's "windowed regex lexer"
   is adopted, but the honest reason is correctness-per-line, not raw speed: `[[ =~ ]]` returns
   the **whole token** and validates the number grammar in the same operation, where a byte loop
   needs a second pass to do either.
2. **The window is 256 bytes, not 2 KB**, with refill below 64. The per-token cost is one match
   plus one `w=${w:m}` shift, and the shift is O(window); 2 KB costs 40 % more than 256 B on
   both bashes. D8 named 2 KB as a planning figure; the measurement overrides it.

**Pinned lexer shape (P1)** — the `hybrid` column above:

* `p` = absolute offset of the unconsumed text, `w = ${s:p:WIN}`; consume with `p=$((p+m));
  w=${w:m}`; refill `w=${s:p:WIN}` only when `${#w} < MINFILL` (≈ once per 192 bytes).
* A token longer than the window (a long string) is handled by growing the window `×4` and
  re-slicing, then resetting it. Proved by the probe's `long-string` self-test (a 5 KB string
  literal, window 256).
* Token kind comes from a `case` on the first byte. Punctuation and `true`/`false`/`null`
  never enter the regex engine (they are ~half of the tokens of a real payload); the two
  regexes are entered only for strings and numbers:

```
str: ^"[^"\]*(\\.[^"\]*)*"
num: ^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?
```

  The string pattern is **unrolled** deliberately: the natural `"([^"\]|\\.)*"` backtracks
  catastrophically on long strings and is forbidden here.
* `MINFILL` (64) exceeds the longest fixed-length token (`false`, 5), so literals and
  punctuation are always fully inside the window and need no edge handling.

### 4.2 `LC_ALL=C` is scoped to the lexer — verified, and it is a correctness requirement

`local LC_ALL=C` inside a function was probed on **both** bashes (`scratchpad` probes
`localeprobe.sh`, `localeprobe2.sh`):

| probe | 5.2.37 | 5.3.9 |
|---|---|---|
| `${#s}` of `é中` inside `local LC_ALL=C` | 5 (bytes) | 5 (bytes) |
| `${s:0:1}` inside | one byte | one byte |
| `[[ é =~ ^..$ ]]` inside (2 bytes, 1 char) | **matches** → regex is in byte mode | **matches** |
| same in the ambient UTF-8 locale | no match (char mode) | no match |
| `${#s}` after the function returns | 2 (chars — restored) | 2 (restored) |
| `[[ $win =~ ^(a.)$ ]]` where `win` ends mid-UTF-8 (`a\xc3`) | **matches**, 2 bytes | matches |
| the same match in the ambient UTF-8 locale | **NO MATCH** | NO MATCH |

The last two rows are the point: a window boundary cuts multi-byte characters in half all the
time, and in a UTF-8 locale `[[ =~ ]]` simply **fails to match** an invalid byte sequence. The
scoped C locale is therefore not an optimisation, it is what makes a windowed lexer correct.
`export` is not needed (and `local LC_ALL=C; export LC_ALL` behaves identically) — no child
process is involved. This satisfies **D6**: the unit self-heals the ambient locale at load time
like every kcl unit, and pins C **locally**, around the lexer only (`kcl/README.md` §1.6).

### 4.3 Unescaping, once per token

The lexer stores the **raw** token slice and unescapes only when it must:

```
if [[ $tok == *\\* ]]; then unescape; else value=${tok:1:${#tok}-2}; fi
```

Payloads are overwhelmingly escape-free, so the common path is one slice. `unescape` is a
single pass with `${tok%%\\*}` / `${tok#*\\}` splits (fork-free), mapping
`\" \\ \/ \b \f \n \r \t` per `jsonscanner.pp:332-341`, and rejecting any other escape with
`SErrInvalidCharacter` — note that the **scanner rejects** unknown escapes even though the
helper `JSONStringToString` (`fpjson.pp:920`) silently drops them; the parse path is the
scanner's, so rejection is the FPC behaviour we port. FPC also accepts `\'`
(`jsonscanner.pp:333`); that is part of its non-strict dialect (O1).

### 4.4 `\uXXXX` and UTF-8, by hand

`printf '\uXXXX'` cannot be used, and the reason is exactly the scoped C locale. Measured
inside `local LC_ALL=C` on **both** bashes:

```
printf -v v 'é中\U0001F600'   →  e9 5c 75 34 45 32 44 5c 55 30 30 30 31 46 36 30 30
```

i.e. `é` degrades to the single raw byte `0xE9` (not UTF-8) and `中` / `\U0001F600`
are left **literally** as backslash-u-…; in the ambient UTF-8 locale the same call yields the
correct `c3 a9 e4 b8 ad f0 9f 98 80`. Leaving the C region per escape is not an option, so the
lexer composes UTF-8 arithmetically:

```
cp < 0x80      -> \xCP
cp < 0x800     -> \x$((0xC0|cp>>6))     \x$((0x80|cp&0x3F))
cp < 0x10000   -> \x$((0xE0|cp>>12))    \x$((0x80|cp>>6&0x3F))  \x$((0x80|cp&0x3F))
else           -> \x$((0xF0|cp>>18))    \x$((0x80|cp>>12&0x3F)) \x$((0x80|cp>>6&0x3F)) \x$((0x80|cp&0x3F))
```

emitted with one `printf -v … '%b'`. Surrogate pairs are composed first:

```
cp = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
```

Verified end to end in the probe: `U+00E9` → `c3 a9`, `U+4E2D` → `e4 b8 ad`, `😀` →
`f0 9f 98 80` (4 bytes), on both bashes.

Two FPC behaviours are ported deliberately rather than "fixed":

* **`\u0000` is dropped.** `jsonscanner.pp:365-369`: with no pending high half, `S:=''` and
  `u1:=u2`, so a `\u0000` contributes nothing and leaves nothing pending. bash cannot hold a NUL
  in a variable anyway, so FPC parity and the bash limit agree. Documented and tested; it is
  **not** a parse error (the draft said it would be — FPC wins, per the review rules).
* **A lone surrogate is emitted as FPC emits it** — `UTF8Encode(WideChar(u1))`, i.e. the 3-byte
  CESU-8 form (`ED A0 BD` for `\uD83D`). The value is then not valid UTF-8; the README says so,
  and the strict option (O1) rejects it instead.

### 4.5 Numbers stay literals

`{"a": 1.50000000000000000001}` survives parse→serialise byte-exact, where FPC would collapse it
through `Double` (`TJSONFloatNumber.GetAsString` → `Str`, `fpjson.pp:2031`). This is a
**documented divergence and strictly more faithful to the input text**; it is also why `AsFloat`
is a validated passthrough (`kk.isNum`) and arithmetic belongs to `kcl/math`.

`AsInteger`/`AsInt64` go through `kk.isInt` (`kcl/README.md` §1.5): decimal only, leading `+`
and leading zeros stripped, **rejected outside int64** — so `9223372036854775807` converts and
`9223372036854775808` gives rc 1 while the literal stays intact in the tree. Pinned test rows:
`-0`, `0`, `-0.0`, `1E400`, `1e-400`, `1.5e3`, `9223372036854775807`, `9223372036854775808`,
`00`, `.5`, `1.`, `1e`, `+1` (the last five are rejects under the default dialect, accepts under
FPC's non-strict one — O1).

---

## 5. Parser

### 5.1 Explicit stack, no recursion

Bash call depth is expensive and the trap in a recursive descent parser is that the *document*
controls the depth. The parser is one token loop over an explicit stack: `st_node[]` (the
container id being filled), `st_type[]` (`o`/`a`), plus a scalar `pendingKey`. Push on `{`/`[`,
pop on `}`/`]`, with the FPC structural check (`jsonparser.pp:100-106`: popping a type that does
not match the open container is a structural error).

### 5.2 Atomic failure

The monotonic-id decision (§3.2) makes atomicity trivial and cheap: `Parse` records
`state[nextid]` as a watermark, and on **any** error unsets every id from the watermark upward
across all six arrays, restores `state[root]` and `state[count]`, and returns rc 1. A failed
parse therefore leaves the document exactly as it was — pinned by a test that parses a good
document, then a bad one, then asserts the first is still intact and serialises identically.

### 5.3 Duplicate keys — parse and Add

* **On `Add`**: FPC raises (`fpjson.pp:3727-3732`). We answer rc 1 + `RESULT=""` and put
  `'Duplicate object member: "<name>"'` (FPC's own `SErrDuplicateValue` text, `:822`) into
  `doc.LastError` + `kk.debug`. The `_index` array makes the check O(1).
* **On parse**: FPC lets the exception out, so the parse fails (`jsonparser.pp:130-137`); with
  `joIgnoreDuplicates` the later value is discarded and the **first wins** (`:138-142`). Both
  are implemented; the default is the FPC default = **reject**, with the position of the
  offending key in the message.
* **On serialise**: no policy is needed and none is invented — the model cannot hold a duplicate
  (`Add` refuses, parse refuses, `Clone` copies a valid tree). A test asserts this rather than
  leaving it implicit.

### 5.4 Max depth — our addition

FPC has no nesting guard (§S11). Ours defaults to **512** and is settable
(`doc.MaxDepth [n]`, `0` = unlimited). Exceeding it is a normal parse error with a position.
Rationale: nesting is the one input dimension where a hostile payload costs unbounded array
growth for a constant number of input bytes, and 512 is far past anything a config or an API
response uses. The default is a **documented divergence from FPC**, not a claimed parity.

### 5.5 Error contract (D2)

* Every failing member: **rc 1**, `RESULT=""`, nothing on stdout or stderr, one `kk.debug` line
  (`kcl/README.md` §1.2).
* **rc 2** is reserved for a malformed *call*: a bad output-array name (via `kk._outName`), a
  member name that is not a plain identifier where one is required, a wrong argument count. A
  handle that is not an integer is rc **1**, not 2 — it is a value the caller may legitimately
  try, and it goes through `kk.isInt` (§9).
* The positioned message is **data**, so it is reachable without the debug switch:
  `doc.LastError` → `RESULT="line L col C: message"` (empty after a successful parse). Message
  texts mirror FPC's resource strings: `SErrInvalidCharacter` (`jsonscanner.pp:26`),
  `SErrOpenString` (`:28`), `SErrDuplicateValue`, `SErrPathElementNotFound`, `SErrStructure`
  (`jsonparser.pp:61`).
* Position tracking must not cost a per-byte counter. The lexer keeps `line` and `lineStart`
  (absolute offset) and updates them **only for chunks that can contain a newline** — whitespace
  runs and string tokens — with `nl=${chunk//[!$'\n']/}; line=$((line+${#nl}))`, fork-free.
  `col = p - lineStart + 1`, matching FPC's 1-based `CurRow`/`CurColumn` (`jsonscanner.pp:191`).

---

## 6. FindPath / GetPath grammar

Read off the three implementations; the port reproduces them exactly.

**Object** (`fpjson.pp:3276-3307`): an empty path returns the node itself. Leading `.`s are
skipped (`While (P<L) and (N[P]='.')` — note the strict `<`, so a path of a single `.` yields
the node itself). The segment runs to the next `.` **or `[`**; an empty segment returns the node
itself; otherwise `Find(name)`, and the remainder — *including* its leading separator — is
resolved against the child. A miss reports the not-found remainder.

**Array** (`fpjson.pp:2512-2542`): a `[` must be the **first** character of the segment;
`P := Pos(']')`; the index is parsed only when `P > 2` (so `[]` is index −1); it must satisfy
`0 <= i < Count`; the remainder is everything after the `]`, so `[0].a` continues as `.a` and
the object rule then skips the dot.

**Scalar** (`fpjson.pp:1489-1497`): any non-empty path against a string/number/boolean/null is a
miss.

**`GetPath`** is `FindPath` plus an error on a miss (`:1526-1533`) — for us, rc 1 plus the
`SErrPathElementNotFound` text in `doc.LastError`, where `FindPath` is silent.

Consequences that get their own tests, because they surprise everyone:

* **A member whose name contains `.` or `[` cannot be reached by a path.** On `{"a.b":1}`,
  `FindPath('a.b')` looks for a member `a` and misses. This is FPC's behaviour and we add no
  escape syntax to "fix" it — `doc.Element node 'a.b'` is the way, and the README says so.
* `FindPath('')` and `FindPath('.')` both return the node itself.
* **A path that starts with `[` against an object returns the object itself.** Traced through
  `:3288-3296`: the segment scan stops immediately on the `[`, so `N` is empty, and the empty-name
  branch is `Result:=Self` — the rest of the path is **discarded, not resolved**. So
  `FindPath('[0]')` on `{"a":1}` yields the object, not a miss. Ported as-is and pinned by a
  test, because nobody would guess it.
* Conversely a path that does **not** start with `[` against an **array** is a miss (`:2541`
  falls through to the scalar rule).
* The array index is parsed by FPC with `StrToIntDef`, which accepts FPC's numeric prefixes
  (`$`, `0x`, `%`). We accept what `kk.isInt` accepts — **decimal with an optional sign** — and
  document the divergence. Reproducing `$1F` inside a JSON path would be parity theatre;
  `tinifile` reproduces `InitVal` where it is genuinely user-visible.

---

## 7. Serialisation

### 7.1 `AsJSON` — byte parity

Default state (`CompressedJSON=False`, `UnquotedMemberNames=False`), from the class vars at
`fpjson.pp:111` and `:606-611`:

| input | FPC `AsJSON` |
|---|---|
| `{"a":1,"b":2}` | `{ "a" : 1, "b" : 2 }` |
| `{}` | `{}` |
| `[1,2]` | `[1, 2]` |
| `[]` | `[]` |
| `{"a":{}}` | `{ "a" : {} }` |

With `CompressedJSON=True`: `{"a":1,"b":2}` and `[1,2]`. FPC's is a **class** property shared by
every instance (`:150`); ours is **per document** (`doc.CompressedJSON true|false`) because a
process-wide switch is action at a distance in a shell — documented divergence (O2).

Escaping on output, from `StringToJSONString` (`fpjson.pp:881-917`) — the character set is
`['"', '/', '\', #0..#31]`:

* `\\`, `\"`, `\b` (#8), `\t` (#9), `\n` (#10), `\f` (#12), `\r` (#13);
* every other control character → `\u00XX` with **uppercase** hex (`HexStr`), e.g. `\u001F`;
* `/` is **not** escaped by default (`Strict=False`); `TJSONString.StrictEscaping` (`:390`) turns
  it into `\/`. Ported as `doc.StrictEscaping true|false`;
* **`#127` (DEL, `\u007F`) is NOT escaped** — it goes out as a raw byte. This is worth stating
  because it is the one control-ish character people expect to be escaped; a test pins it;
* non-ASCII goes out as raw UTF-8, never as `\u` — FPC never re-escapes.

### 7.2 `FormatJSON`

`doc.FormatJSON [node] [options] [indent]`, `DefaultFormat=[]`, `DefaultIndentSize=2`
(`fpjson.pp:74-75`); options are the six `TFormatOption` names, comma-separated. From
`:2632-2667` (array) and `:3592-3650` (object):

* multiline unless `foSingleLineArray` / `foSingleLineObject`; indent is `CurrentIndent+Indent`,
  spaces unless `foUseTabchar`;
* the member separator is `' : '` normally, `':'` under `foSkipWhiteSpace`, and `': '` under
  `foSkipWhiteSpace + foSkipWhiteSpaceOnlyLeading`;
* element separator `','+lineBreak+indent` when multiline, else `', '` / `','`;
* `foDoNotQuoteMembers` drops the quotes around names;
* an empty container is `{}` / `[]` whatever the options;
* the convenience sets are ported too: `AsJSONFormat`, `AsCompressedJSON`, `AsCompactJSON`
  (`:76-78`).

`sLineBreak` is **LF**, always. FPC on Windows would emit CRLF; matching that would poison every
fixture in a repo that is edited on both platforms. Documented divergence.

The serialiser is iterative (an explicit stack over `_kids`), for the same reason as the parser,
and it builds into one accumulator with `+=`.

---

## 8. `ParseFile`

No byte loop and no `cat`:

```
mapfile -d '' -t __chunks < "$path"      # splits on NUL; a NUL-free file is ONE element
```

* `${#__chunks[@]} > 1` ⇒ the file contains a NUL ⇒ rc 1, `'file contains NUL bytes'`. This is
  an exact detection, not a guess, and it costs nothing.
* an unreadable/missing path is rc 1 with the path in the debug message; a directory likewise.
* the text then goes through exactly the same lexer as `Parse` — there is one code path, and a
  test asserts `ParseFile f` and `Parse "$(<f)"` produce identical `AsJSON`.
* **BOM**: FPC strips `EF BB BF` only under `joBOMCheck`, which is not in `DefaultOptions`
  (`jsonscanner.pp:162`, `:57`). Same here: off by default, available as an option.

---

## 9. The kcl contract, applied from day one

`kcl/README.md` §1, line by line — this table is the P1–P7 checklist and the contract test's
table of contents:

| § | Rule | fpjson |
|---|---|---|
| 1.1 | value via `RESULT`, never stdout; data round-trips verbatim | every member; `printf '%s'`, never `echo`. String values carry newlines and `-e`/`-n` — the round-trip test uses all three |
| 1.1 | static units need `static proc` + `_ret` | **n/a** — fpjson is an *instance* class, so `func` + `kk._return` is correct as-is |
| 1.2 | rc 1 + `RESULT=""` + silence; `kk.debug` for the diagnostic; rc 2 = malformed call | §5.5 |
| 1.3 | predicates answer by rc | `doc.IsNull`, `doc.Has`, `doc.IsValid`, `doc.Contains` |
| 1.4 | `set -eu` clean: `${_FPJSON_SOURCED:-}`, `${2:-}`, `(( … )) \|\| :`, no trailing `&&` list | every arithmetic statement in the lexer is `x=$((…))` (an assignment, always rc 0) rather than `(( x++ ))` — the hot loop is where this bites |
| 1.5 | caller-supplied numbers through `kk.isInt`/`kk.isNum` **before** `(( ))` or `${arr[i]}` | **critical here**: every member takes a handle, and `${doc}_type[$h]` with `h='x[$(touch pwn)]'` *executes*. `kk.isInt "$1" h \|\| return 1` is the first line of every member that takes a handle or an index; `kk.isNum` guards `AsFloat` |
| 1.6 | UTF-8 assumed; byte semantics pinned **locally** | §4.2 — the load-time self-heal is the standard four lines; `LC_ALL=C` appears only inside the lexer, the unescaper and the serialiser's escape scan |
| 1.7 | output arrays by name, validated by `kk._outName` before the nameref binds | `doc.Items`, `doc.Names`, `doc.Keys`, `doc.Paths`; the unit passes its own prefix `__fpj_`, and additionally refuses the six per-document array names |
| 1.8 | no forks in hot paths | the whole pipeline is fork-free; the `PATH=''` test covers parse → FindPath → AsJSON → delete, and `$BASHPID` is asserted unchanged |
| 1.9 | the destructor frees every extra per-instance array | §3.5, with the 10k teardown test |

---

## 10. API surface

`TJSONData` is the document class; `node` is always an integer handle, and it defaults to the
root when omitted.

| member | kind | returns |
|---|---|---|
| `TJSONData.new doc` / `doc.delete` | ctor/dtor | — |
| `doc.Parse TEXT` | func | `RESULT` = root handle; rc 1 on a malformed document |
| `doc.ParseFile PATH` | func | as `Parse` (§8) |
| `doc.LastError` | func | `RESULT` = `line L col C: message`, `""` after a clean parse |
| `doc.Root` | func | `RESULT` = root handle (0 for an empty document) |
| `doc.TypeOf node` | func | `RESULT` = `jtObject`\|`jtArray`\|`jtString`\|`jtNumber`\|`jtBoolean`\|`jtNull` |
| `doc.Count node` | func | `RESULT` = child count (0 for scalars, per `TJSONData.GetCount` `:1483`) |
| `doc.Item node i` | func | `RESULT` = child handle; rc 1 out of range |
| `doc.Name node i` | func | `RESULT` = member name (object only) |
| `doc.Element node name` / `doc.Find node name` | func | `RESULT` = child handle; rc 1 miss |
| `doc.IndexOfName node name` | func | `RESULT` = index; rc 1 miss (`:3122`) |
| `doc.Has node name` | predicate | rc |
| `doc.FindPath node path` / `doc.GetPath node path` | func | §6 |
| `doc.AsString\|AsInteger\|AsInt64\|AsFloat\|AsBoolean node` | func | `RESULT` = value; rc 1 when FPC would raise `EConvertError` |
| `doc.IsNull node` | predicate | rc |
| `doc.AsJSON [node]` | func | `RESULT` = compact JSON (§7.1) |
| `doc.FormatJSON [node] [options] [indent]` | func | `RESULT` = formatted JSON (§7.2) |
| `doc.ObjAdd node name type value` | func | `RESULT` = the **new child handle**; rc 1 on a duplicate name |
| `doc.ArrAdd node type value` / `doc.ArrInsert node i type value` | func | `RESULT` = new child handle |
| `doc.ObjDelete node name\|index`, `doc.ArrDelete node i`, `doc.Remove node child`, `doc.Clear node` | proc | rc |
| `doc.Extract node name\|index` | func | `RESULT` = detached subtree handle (`:3167`) |
| `doc.Clone node [destDoc]` | func | `RESULT` = handle in the destination document |
| `doc.Items node OUT` / `doc.Names node OUT` | func | writes the array, `RESULT` = count (§1.7) |
| `doc.ForEach node cb` | proc | snapshot of the child list, cb per child |
| `doc.CompressedJSON [true\|false]`, `doc.StrictEscaping [true\|false]`, `doc.MaxDepth [n]`, `doc.Options [list]` | property-ish func | read with no argument, set with one |

`ObjAdd` returning the **handle** where FPC returns the insertion index is the one deliberate
signature change: the handle is what every other member consumes, and the index is
`Count-1`/`IndexOfName`. Documented in the README's divergence table.

---

## 11. Test model

* **FPC seeds:** `packages/fcl-json/tests/` (`testjson.pp` — the fpcunit data-model tests) are
  mined at P1 and become the parity rows for `Add`/`Delete`/`FindPath`/`AsXxx`.
* **JSONTestSuite (seriot.ch) subset**, vendored into `tests/fixtures/` with provenance: every
  applicable `y_` (must accept) and `n_` (must reject); NUL-bearing cases become
  expected-reject rows; every `i_` case gets a **decided, documented, tested** answer.
* **Properties:** parse → `AsJSON` → parse fixpoint; number-literal preservation; insertion
  order stability across mutation; `Clone` independence (mutating the clone leaves the original
  byte-identical).
* **Torture:** 1 000-deep nesting (and the depth guard at 512), a 64 KB string value, a 10 000
  element array, every escape, multi-byte and astral UTF-8, exotic member names (`''`, spaces,
  `.`, `[`, `"`, `\x1f`, emoji) — the last group cross-checked against the FindPath grammar
  (§6).
* **Positions:** a malformed-input matrix asserting exact `line:col`.
* **Contract:** `NNN_Contract.sh` per `kcl/README.md` — `set -eu` load and main path, injection
  handles (`'x[$(touch pwn)]'`), `-n`/`-e`/newline values through `$( )` and direct calls, every
  `${doc}_*` array gone after `.delete`, `PATH=''` zero-fork run, `bash -n` + dangling-quote
  check.
* Dual-bash everywhere; non-FPC decisions land as `TEST_COVERAGE_NOTES.md` rows citing the
  JSONTestSuite id.

---

## 12. Phases

Each phase: red-first tests (`kcl/PLAN.md` §4), then the code; gate = unit suite 0 FAIL on
**5.2.37 and 5.3.9** sequentially, master sweep 0 FAIL on both (all `[FAIL]` lines grepped,
never the tail), `set -eu` smoke, `bench.sh` no metric worse than the previous phase, `git
status` clean, no `.ckk`/`/tmp` growth. Then STOP and wait for "go".

* **P0 — design + probes. DONE 2026-09-09** (this document). Decisions D8-1…D8-6 (§13),
  measurements §3.4/§4.1/§4.2, `bench/lexer_probe.sh` written and green on both bashes, gate
  20 KB ≤ 1 s met at 290 ms. No unit code — deliberately.
* **P1 — lexer.** The hybrid tokenizer, positions, unescape incl. `\u`/surrogates, number
  validation, `LC_ALL=C` scoping, skeleton class + runner. Tests: token corpus with exact
  offsets, every escape, the `n_` cases that are lexical, `${#}`-vs-bytes under a UTF-8 locale.
  Extra gate: the probe's `hybrid` numbers reproduced by the real lexer within 2×.
* **P2 — parser → storage.** Explicit stack, the six arrays, atomicity (§5.2), duplicate policy
  (§5.3), depth guard (§5.4), `y_`/`n_` corpus verdicts. Extra gate: a failed parse leaves the
  document byte-identical.
* **P3 — navigation + getters.** `FindPath`/`GetPath` (§6), `TypeOf`/`Count`/`Item`/`Name`/
  `Element`/`IndexOfName`, the `AsXxx` coercions (S8), `IsNull` (S12), `ForEach`, `Items`/`Names`
  output arrays. Extra gate: exotic member names, `kk._outName` refusals.
* **P4 — serialisation.** `AsJSON` byte-parity (§7.1), `FormatJSON` (§7.2), fixpoint and
  literal-preservation proofs, and the two escaping rows nobody expects: control characters
  become **uppercase** `\u00XX`, and DEL (`#127`) is **not** escaped at all.
* **P5 — mutation.** Typed `ObjAdd`/`ArrAdd`/`Insert`, `Delete`/`Remove`/`Clear`/`Extract`,
  `Clone` (S9), order preservation, `_index` and `_parent` consistency after every mutation
  (an invariant checker used by the tests).
* **P6 — hardening.** Full corpus, deep/long/pathological inputs, `i_` decisions, the
  error-position matrix, the **10k-node teardown test** (≤ 50 ms, §3.4), zero-fork `PATH=''`
  pipeline, injection matrix.
* **P7 — docs, bench, closeout.** `README.md` (API, positioning, jq-vs-fpjson guidance,
  divergence table), `docs/TJSONData.md` (upstream FPC reference with the standard kcl header),
  `bench.sh` (parse 1/10/100 KB, `GetPath` hot, `AsJSON`, informational `jq`-fork comparison),
  timed through `TStopwatch.getTimeStamp` (source `../tstopwatch/tstopwatch.sh` — do not
  hand-roll a clock), `TEST_COVERAGE_NOTES.md`, ledger COMPLETE.
* **P8 — OPTIONAL awk co-process tokenizer.** Own owner gate, only if real usage demands it.
  Same token interface, corpus equivalence against the pure lexer, the kcl/math engine's
  lifecycle lessons (temp-file program feed, `TMPDIR` fallback, lazy start, the `$( )` subshell
  caveat). The review measured a one-shot `awk` tokenize of 96 KB at 1.7–4.5 s **including the
  fork** — i.e. no better than the pure lexer at that size; a persistent co-process only starts
  paying above ~20 KB. This phase stays last and stays optional.

---

## 13. Decisions recorded by P0 (D8-1 … D8-6)

| id | decision | basis |
|---|---|---|
| **D8-1** | Handles are **monotonic, never recycled**; `0` = no node. No free list. | a recycled id makes a stale handle address a different node silently; bash has no cheap generation counter. Cost documented (§3.2), remedy = `Clone` |
| **D8-2** | Window is **256 bytes**, refill below **64**, grow ×4 for oversized tokens — not the 2 KB named in D8 | sweep §4.1: 2 KB is ~40 % slower on both bashes |
| **D8-3** | Lexer = **first-byte `case` + regex for strings/numbers only** ("hybrid"), not one regex per token | §4.1: 290 ms vs 368 ms at 20 KB on 5.2; and punctuation is half the tokens |
| **D8-4** | `\u0000` is **dropped** (FPC), not a parse error as the draft said | `jsonscanner.pp:365-369`; FPC wins over the draft per the review rules |
| **D8-5** | Max depth **512**, settable, `0` = unlimited — an addition, FPC has none | §5.4 |
| **D8-6** | `CompressedJSON`/`StrictEscaping` are **per document**, not class-wide as in FPC | a process-wide switch is action at a distance in a shell (§7.1) |

---

## 14. Bash traps to respect

1. `local LC_ALL=C` around the lexer — proven to switch `${#s}`, `${s:i:n}` **and** `[[ =~ ]]` to
   bytes and to be restored on return, on both bashes (§4.2). Never leak it to a child.
2. `${s:i:1}` over a **large** string is O(n). Windows, always (§4.1).
3. `"([^"\]|\\.)*"` backtracks catastrophically; use the unrolled form (§4.1).
4. `printf '\uXXXX'` is unusable inside the C-locale lexer (§4.4) — hand-rolled UTF-8.
5. `(( x++ ))` returns 1 when `x` was 0 and aborts under `set -e`; in the lexer's hot loop use
   `x=$((x+1))` (an assignment) rather than `|| :` noise.
6. Every handle and index is a caller-supplied number reaching `${arr[$h]}` — `kk.isInt` first,
   always (`kcl/README.md` §1.5).
7. Member **names** may contain any byte; only integer child ids are ever joined (§3.3).
8. The per-document arrays are globals named from the instance; `_data`, `_class` and `_items`
   belong to kklass — never use them, and refuse them in `kk._outName` (`kcl/README.md` §1.7).
9. `RESULT` must be lossless: string values carry trailing newlines, and `$( )` strips them —
   direct call + `RESULT` is the documented lossless form.
10. `kk._return ""` on every failing path of a `func`.
11. Never edit the unit during a sweep.

---

## 15. Open questions for the owner

Defaults are already chosen and implemented as written above; these three are flagged because
each is a deliberate **divergence from FPC's default** and the owner may want the other side.

* **O1 — dialect default.** **Owner decision 2026-09-09: strict RFC 8259 by default (as planned).** FPC's `DefaultOptions=[joUTF8]`, i.e. `joStrict` is **off**: FPC
  accepts single-quoted strings, unquoted/identifier member names, case-insensitive `TRUE`,
  raw control characters inside strings, leading zeros, `.5` and `1.e5`. This plan defaults to
  **strict RFC 8259** (= `joStrict` on) and offers FPC's lenient dialect through
  `doc.Options joStrict=false`, because silently accepting `{name: .5}` from an API is a bug
  amplifier. If the owner prefers exact FPC defaults, only the default option set changes —
  both dialects are implemented and tested either way.
* **O2 — `CompressedJSON` scope** (D8-6): **Owner decision 2026-09-09: per document (as planned).** per document here, class-wide in FPC. A class-wide
  switch is reproducible in kklass (a static property) if byte-parity of the *API shape* matters
  more than the shell hygiene argument.
* **O3 — `ObjAdd` return value:** **Owner decision 2026-09-09: the handle (as planned).** the new child **handle** here, the insertion **index** in FPC.
  Both are one line; the handle is what the rest of the API consumes.

---

## 16. Deliverables

`kcl/fpjson/`: `fpjson.sh`, `PLAN.md`, `fpjson_ledger.json`, `README.md`, `docs/TJSONData.md`,
`bench/lexer_probe.sh` (P0, done), `bench.sh` (P7), `TEST_COVERAGE_NOTES.md`,
`tests/001…` + `tests/tests.sh`, `tests/fixtures/` (vendored corpus subset with provenance).
