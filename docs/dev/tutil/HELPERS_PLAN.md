# TUtil family — convenience methods plan (HELPERS)

Status: **v2, owner agreed to the cut 2026-10-22; H1 DONE 2026-10-22 (launch
task L2.7-H); H2 DONE 2026-10-30 (launch task L6.0: TGrep `quiet`,
`TGrep.contains`, `TGrep.countMatching`, `TFind.quoteGlob`; see §3 and
`helpers_ledger.json`).** v1 proposed ~30 members
across six wrappers; the critique (§7) cut it to the members that spare the
caller **escaping data**. Everything else was an alias of an existing property
or sink.

## 0. Why

Each wrapper models its tool's **options** as typed properties, but the tool's
**language** is still the caller's job. Replacing a string with TSed today:

```bash
TSed.edit 's/C:\\dir\/a\.txt/D:\\x/g' f.txt     # escape BRE + delimiter + `&` by hand
```

A `.`, `*` or `/` in the text, an `&` or `\1` in the replacement, and sed
silently does something else. The new members take **data** (literal text) and
the wrapper does the escaping, so the caller cannot get it wrong.

## 1. Principles

1. **Data in, never syntax.** Every new member treats its text literally. The
   regex forms already exist (`expr`, `addExpr`, `edit`) and get no twin.
2. **Two layers, one implementation.** An instance builder stores the raw data;
   `buildArgv` escapes it. A static = throw-away instance + builder + `run`,
   exactly the `TSed.edit` pattern (`__tsd_e_${BASHPID}_${__TSD_SEQ}`, sandbox
   forced, ≥ 1 path or rc 2, nested-safe).
3. **Escape at build time, not at call time.** `quoteRe` depends on `extended`,
   and a builder may be called before `extended = 1`. So `${inst}_exprs`
   becomes a list of **tagged records** and the escaping happens in `buildArgv`
   (§2.2).
4. **Flags = TStringHelper's vocabulary** (`rfReplaceAll`, `rfIgnoreCase`) with
   its rule: no FLAGS = every occurrence; with FLAGS only what it names.
5. **Escape helpers are public**, so a caller writing their own `addExpr` has
   the wrapper's tool.
6. **Family contracts hold**: rc 2 = malformed call, nothing ran, stdin
   untouched; rc 1 = the tool failed, raw status in `lastRc`; the CR contract
   (DL11); both bashes (5.2.37 / 5.3.9); the sandbox stays forced in statics —
   escaping makes FROM/TO literal, but `addExpr` is still there, so the sandbox
   is still the wall; no stray processes.
7. **Reserved names** (tutil README §4) are not touched.

## 2. H1 — TSed (before the launch)

### 2.1 Members

| Member | Kind | sed it builds |
|---|---|---|
| `TSed.quoteRe TEXT [ere]` | static, RESULT | TEXT as a literal regex. BRE escapes `\ / . * [ ^ $`; with a second argument `ere` (exactly that word) also `+ ? ( ) { } \|`. A newline becomes `\n`. A static has no instance, so the dialect is an argument |
| `TSed.quoteRepl TEXT` | static, RESULT | TEXT as a literal replacement: escapes `\ / &`; a newline becomes `\`+newline |
| `addReplace FROM TO [FLAGS]` | proc | `s/<quoteRe FROM>/<quoteRepl TO>/g` — `g` unless FLAGS lacks `rfReplaceAll`, `I` with `rfIgnoreCase`; the dialect follows `extended` at build time. Empty FROM → rc 2 (sed would take "the previous regex"). FROM containing a newline with `nullData = 0` → rc 2 (it can never match a line) |
| `TSed.replace FROM TO PATH...` | static, stream | literal, every occurrence, to stdout — like `edit`, **never** in place |
| `TSed.replaceInFile FROM TO PATH...` | static, `run` | literal, in place, **no backup** (`backupSuffix` is one instance line for those who want one); sed rewrites the file even with zero matches (mtime changes) — documented |

Naming: `replace` already means a value in TStringHelper and FPC's file
replace in TFile. Here it is a **stream**, consistent with `edit`; the
in-place form carries `InFile` in its name so nothing destructive hides behind
the short verb.

### 2.2 `_exprs` becomes tagged records

Today `${inst}_exprs` holds ready expressions ([tsed.sh:311](../../../tsed/tsed.sh#L311)).
To keep call order between `addExpr` and `addReplace` and escape at build time,
each element becomes `TAG<TAB>…`:

| record | meaning |
|---|---|
| `e<TAB>EXPR` | an `addExpr` element (EXPR may be empty — the identity) |
| `r<TAB>FROM<TAB>TO<TAB>FLAGS` | an `addReplace` element, raw |

A TAB inside FROM/TO breaks that layout, so the field separator is a byte that
cannot occur in the caller's data: the record is stored as three **separate**
parallel arrays instead if the probe shows TAB is reachable (it is: a TAB in
FROM is legitimate). Decision taken here: **parallel arrays** `${inst}_exprs`
(tag or raw expr), `${inst}_rfrom`, `${inst}_rto`, `${inst}_rflags`, indexed
alike; `_exprs[i]` holds `EXPR` for an `e` record and the literal `__tsd_r__`
marker for an `r` record. The three new suffixes go into `TUTIL_OUT_SUFFIXES`
(tsed README §8); `Destroy` frees them; `clearExprs` empties all four.
`tsed/tests/004` and `005` pin `_exprs` and must be updated — part of H1.

### 2.3 Measured so far (GNU sed 4.9, bash 5.2.37 AND 5.3.9)

The escape sets above round-trip FROM `a.b*c[d]e^f$g\h/i+j?k|l(m){2}&` and TO
`X&Y\1/Z<newline>W` in BRE and `-E`, byte-exact by `od -c`, on both bashes. The idiom that works
is `bs='\'; s=${s//"$c"/"$bs$c"}` with `patsub_replacement` on (the quoted
replacement keeps `&` literal). Probe: scratchpad `esc_probe.sh`, to be moved
into the test file.

### 2.4 Edges H1 measures (not guesses), on both bashes

* a CR inside FROM in text mode — the DL11 prelude strips the line-end CR
  before the script, so a FROM ending in CR never matches: document, do not
  "fix";
* `nullData = 1`: the newline is data, `\n` in quoteRe matches it; FROM with a
  newline is legal there;
* multibyte FROM under `LC_CTYPE=C.UTF-8` and under `C`;
* `addReplace` before and after `extended = 1` → the same argv;
* `addReplace` interleaved with `addExpr` keeps call order;
* `rfIgnoreCase` → the `I` flag (GNU; BSD sed is out of scope per tsed D4);
* `inPlace` + `addReplace`: the derived `-b` keeps CRLF on disk (owner Q5);
* zero matches: rc 0, output identical, `replaceInFile` still rewrites;
* `TSed.replace` in all three positions (terminal, lastpipe, `--` form) like
  `edit`; nested inside an outer sink's callback;
* `quoteRe`/`quoteRepl` under `$( )` print once, direct call silent.

### 2.5 Deliverables

* `tsed.sh`: the five members, the storage change, registry suffixes.
* `tsed/tests/008_Helpers.sh` (004–007 exist; + updates to 004/005); every
  case on both bashes; GNU banner gate first as in 005.
* `tsed/README.md`: §7 extended ("The one-liners"), a new "Literal replace"
  section, cross-reference to `TStringHelper.replace` / `TRegex.replace` for
  strings in a variable; §8 updated for the new suffixes.
* `tsed/PLAN.md` gets a §H1 pointer here; `tsed_ledger.json` entry.
* `bench.sh`: one line per new static (cost = one instance build + one fork,
  tutil PLAN §6; no new budget).
* `tools/gate.sh` PASS on both bashes; `strays_win.ps1` clean; one kcl commit,
  one kbool bump. No push without owner go.

Who: **Opus** worker, then an independent read-only Opus **critic** (DL9a: the
storage change touches every TSed test).

## 3. H2 — after L5 (post-launch batch)

Separate cards, Sonnet high, built from H1's pattern.

| Unit | Member | Notes |
|---|---|---|
| TGrep | `var quiet` (`-q`) | the missing option; `buildArgv` only — there is no deny-list in `TUtil.addArg` (checked at L6.0), `quiet` is not a reserved name; grep `-q` exits 0 at the first match even if another operand failed (measured, pinned) |
| TGrep | `TGrep.contains TEXT PATH...` | static, **rc only**: `-r -F -q`; rc 0 found, rc 1 not found **or** tool error + one `kk.debug` line — the family mapping, no new rc meaning. Who must tell the two apart builds an instance and reads `lastRc` |
| TGrep | `TGrep.countMatching TEXT PATH...` | static, RESULT: `-r -h -F` + the existing `count` sink — **no parsing** of `file:count` |
| TFind | `TFind.quoteGlob TEXT` | escapes `* ? [ \` for `-name`; proved against GNU find (what TFind resolves everywhere; no BSD find probe — TFind never runs BSD find); the backslash cases `SKIP:` on Windows, where a name cannot hold `\` |

## 4. Dropped (v1 → v2), with the reason

| Member | Reason |
|---|---|
| `addReplaceRe`, `replaceRe` | the regex form is `addExpr`/`edit`; a delimiter cannot be handled safely on raw regex syntax (`\/` is ambiguous) |
| `addDeleteLines`, `deleteLines`, `range`, `addInsert`, `addAppend` | not escaping problems; `edit '/x/d'`, `edit -n 'N,Mp'` are one line |
| `TGrep.searchText`, `filesWith` | `fixed = 1`, `filesOnly = 1` exist |
| `THead.dropLast`, `firstLine`, `TTail.skip`, `lastLine` | aliases of `lines = -N` / `+N` and of the `first` sink |
| `TFind.files`, `dirs`, `byExt` | `type = f` / `d` exist |
| TAwk presets (`useColumns`, `useSum`, `useUnique`, statics) | canned programs, not syntax hiding — a mini-library with no natural boundary; `TAwk.sum` would also need `%.17g` (gawk prints `1234567.8` as `1.23457e+06` under OFMT). If wanted: its own plan |

## 5. Decisions

| # | Decision | By |
|---|---|---|
| D1 | Scope = §2 + §3; §4 dropped | owner 2026-10-22 (agreed to the cut) |
| D2 | H1 before the launch (the README pitch uses `TSed.replace`); H2 after L5 | owner 2026-10-22 |
| D3 | `replaceInFile` makes no backup by default | SV |
| D4 | predicates answer rc 0/1; a tool error is rc 1 + debug line (family mapping), never rc 2 | owner 2026-10-22 (critique §2) |
| D5 | `quoteRe` dialect is an explicit `ere` argument on the static, `extended` on the instance | SV |
| D6 | FROM with a newline in line mode is rc 2 | SV |
| D7 | flag tokens = TStringHelper's | SV |

## 6. Ledger

`tutil/helpers_ledger.json`: H1, H2 with phase, status, SHAs, gate ids —
created at H1 dispatch.

## 7. The v1 critique (kept for the record)

Scope inflated (aliases of existing properties and sinks); D4 broke the rc 2
contract; `countMatching` parsed `file:count` instead of using the `count`
sink; the Re form's delimiter was unsafe; the static `quoteRe` referred to a
non-existent instance setting; escaping at call time ignored `extended`;
`TAwk.sum`'s numeric claim was wrong (measured); six gated phases competed with
the launch queue; four of seven decisions were conventional defaults.
