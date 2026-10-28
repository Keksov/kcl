#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%tsed.sh}../../kbool.sh" || return
kk.unit tsed || return $__kk_unit_rc

# Locale self-heal (kcl/README.md §1.6). A path, an expression and the bytes sed
# emits are data and pass through verbatim, so character semantics are part of
# this unit's contract: an empty environment means the C locale.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# A unit (kklass/USES_PLAN.md §7.4, phase U4): the two header lines at the
# top load kbool.sh when needed and make a repeated `source` a no-op, also
# under `set -eu` (they replaced the D7 re-source guard). Dependencies come
# through kk.uses.
# The base class. `tutil` transitively brings kklass's Pascal front-end and
# `tpipe`; both are units (loaded once per process). This is the ONLY
# dependency of the unit.
kk.uses tutil || return

# Register this unit in TUtil's two out-name registries (PLAN §2.1):
#   * the local prefix `__tsd_` — bash scopes locals DYNAMICALLY, so a caller
#     array named `__tsd_v` would bind the scratch nameref a member body holds;
#   * the suffix `_exprs` — `${inst}_exprs` is this unit's own storage, and
#     measured, `s.toArray s_exprs` turned the records into the NEXT run's
#     script (with `sandbox = 0` a data line `e …` became a command);
#   * the suffixes `_rfrom`, `_rto`, `_rflags` — the raw `addReplace` data kept
#     next to `_exprs` (HELPERS_PLAN §2.2), the same storage for the same reason.
# Each append is idempotent (only if absent), and the scratch globals are
# released right after, so the unit leaves exactly `__TSD_SEQ` behind.
declare -g __tsd_seen=0
declare -g __tsd_p=''
declare -g __tsd_sfx=''
for __tsd_p in "${TUTIL_OUT_PREFIXES[@]}"; do
    if [[ "$__tsd_p" == "__tsd_" ]]; then
        __tsd_seen=1
    fi
done
if [[ "$__tsd_seen" != "1" ]]; then
    TUTIL_OUT_PREFIXES+=( __tsd_ )
fi
for __tsd_sfx in _exprs _rfrom _rto _rflags; do
    __tsd_seen=0
    for __tsd_p in "${TUTIL_OUT_SUFFIXES[@]}"; do
        if [[ "$__tsd_p" == "$__tsd_sfx" ]]; then
            __tsd_seen=1
        fi
    done
    if [[ "$__tsd_seen" != "1" ]]; then
        TUTIL_OUT_SUFFIXES+=( "$__tsd_sfx" )
    fi
done
unset -v __tsd_seen __tsd_p __tsd_sfx

# Monotonic sequence for `TSed.edit`'s throw-away instance name (PLAN §2.7): a
# FIXED name is deleted out from under an outer `edit` by a nested one, so the
# name is `__tsd_e_${BASHPID}_${__TSD_SEQ}`. Same idiom as TGrep's `__TG_SEQ`.
declare -g __TSD_SEQ=0

# ---------------------------------------------------------------------------
# TSed — the GNU sed 4.9 wrapper over TUtil.
#
#     source kcl/tsed/tsed.sh
#
#     TSed.edit 's/foo/bar/' notes.txt      # the one-liner, streamed, sandboxed
#
#     TSed.new s 's/a/A/' in.txt            # or an instance, for options
#     s.addExpr '/^#/d'                     # more expressions, in order
#     s.extended = 1                        # -E (always before the first -e)
#     s.toArray lines                       # RESULT = ${#lines[@]}
#     s.inPlace = 1; s.backupSuffix = .bak  # in-place: `run` only
#     s.run
#     s.delete
#
# ---- The pinned argv (PLAN §1.2) ------------------------------------------
#   sed [--sandbox] [-E] [-n] [-s] [-z] [-b] [-i[SUFFIX]] [EXTRA OPTIONS]
#       [CR prelude: -e s/<CR>$// -e t__tsd_cr -e :__tsd_cr]
#       [-e EXPR] [-e X ...] [-f FILE] [-- PATH...]
#
#  * sed compiles each `-e` WHEN IT READS IT, with the flags known so far:
#    `sed -e 's/(/X/' -E` silently runs the expression as BRE. So EVERY option
#    — typed or extra — precedes the first `-e`;
#  * `expr` is emitted first, then the `addExpr` list in call order, then
#    `-f scriptFile`; `--` appears only with at least one path;
#  * `-b` is emitted when `binary == 1` OR `inPlace == 1` OR `nullData == 1`
#    (owner Q5): in text mode sed rewrites CRLF to LF ON DISK under `-i` (even
#    the identity) and strips a CR inside a NUL record under `-z`. The derivation
#    lives here only; the `binary` property is never written;
#  * without that `-b` the build is TEXT mode: the line-end CR of a CRLF input
#    never reaches the SCRIPT, on any platform — cygwin/msys sed drops it
#    itself; elsewhere the build puts the prelude `-e 's/<CR>$//' -e
#    't__tsd_cr' -e ':__tsd_cr'` after the extras, before the first script word
#    (plus `-n` for a `#n` first line). The label `__tsd_cr` is reserved. No
#    output strip: a CR the script writes is kept (tutil README §3, DL11);
#  * `-i` takes its suffix ATTACHED (`-i.bak`); `*` in the suffix is replaced
#    by the OPERAND AS GIVEN, directory part included (`bak_*` on `d/f` is
#    `bak_d/f`), `/` makes it a directory (`bk/*`); a missing directory is the
#    tool's rc 4 with the file untouched (measured at P0).
#  * `--sandbox` is emitted unless `sandbox` is EXACTLY `0` — it fails closed,
#    the one deliberate exception to the family boolean rule (owner Q1).
#
# ---- rc 2 at buildArgv: nothing runs, one kk.debug line (PLAN §2.2) --------
#   * `cmd` empty;
#   * NO script at all (`expr` '', the list empty, `scriptFile` '') — sed would
#     take the first path AS the script. The identity is `addExpr ''`;
#   * `inPlace = 1` with no path, or with the path `-`;
#   * `backupSuffix` non-empty with `inPlace = 0`, or equal to `*`;
#   * an extra on the Q6 deny-list: any spelling sed's getopt reads as `-i`,
#     `-z`, `-e`, `-f`, `-n`, `-s`, `-E`/`-r`, `-b` or `--sandbox` — see
#     `tsed._denied`. `--posix`, `-u`, `-l N`, `--follow-symlinks`, `--debug`
#     pass;
#   * `--` among the extras: it ends sed's options, and every expression after
#     it would become an operand (the wrapper emits its own `--`);
#   * an `addReplace` element with an EMPTY FROM (sed would reuse the previous
#     regex), with a newline in FROM while `nullData` is not `1` (a line never
#     holds one), or with a FLAGS word that is not `rfReplaceAll`/`rfIgnoreCase`.
#     (`addReplace` itself refuses only MORE than three arguments, at call time.)
#
# ---- Literal replace (kcl/tutil/HELPERS_PLAN.md §2, H1) --------------------
# `addReplace FROM TO [FLAGS]` stores the RAW text; `buildArgv` escapes it, so
# the dialect is the one `extended` holds at BUILD time:
#     -e 's/<quoteRe FROM>/<quoteRepl TO>/[g][I]'
# Storage: `${inst}_exprs` keeps call order for `addExpr` AND `addReplace`; an
# `addReplace` element is the marker `__tsd_r__` there, its raw data sits in the
# parallel arrays `${inst}_rfrom`, `${inst}_rto`, `${inst}_rflags` at the SAME
# index (an `addExpr` element holds '' in all three). No FLAGS = every
# occurrence and is stored as `rfReplaceAll`; a FLAGS argument (even '') means
# only what it names (TStringHelper's rule). `rfIgnoreCase` (sed's `I`) folds
# non-ASCII letters only under a UTF-8 LC_CTYPE; plain matching is the same in
# every locale. `TSed.quoteRe` / `TSed.quoteRepl` are the same escapers as
# statics (`quoteRe TEXT WORD` with WORD other than exactly `ere` is rc 2 — it
# fails closed); `TSed.replace` / `TSed.replaceInFile` are the one-liners, built
# like `TSed.edit`.
# RESERVED WORDS: the label `__tsd_cr` (the CR prelude) and the marker
# `__tsd_r__` (`addExpr '__tsd_r__'` is rc 2, nothing appended).
#
# ---- The five sinks (PLAN §2.4) --------------------------------------------
# `inPlace = 1`, or `--debug` among the extras, makes every sink answer rc 2
# with nothing run (`_lastRc` untouched): in-place writes nothing to stdout,
# `--debug` writes its trace INTO it. `run` is the member for both. Otherwise
# the base sink runs, through the rc-PRESERVING spelling (thead §6).
#
# ---- mapRc (owner Q3) ------------------------------------------------------
#   0 -> 0;  1, 2, 4 -> 1 + one kk.debug line ("sed exited N (a sed error, or
#   the script's q/Q N)");  127 -> the base wording;  anything else — a
#   script's `q N`/`Q N` — -> 1 SILENT, the raw value in `lastRc`.
#
# ---- Traps this unit is written around ------------------------------------
#  * The constructor calls `parent.constructor sed` EXPLICITLY (`inherited` in
#    a constructor forwards "$@" and would make EXPR the command), then
#    `tutil._gnu sed` (cmd = the GNU sed ktool resolved, or '' with the reason).
#  * EVERY declared var is assigned in `Create`; `sandbox` to 1.
#  * No `var` is named like a TUtil or kklass member.
#  * Booleans are compared as strings (`[[ "$x" == 1 ]]`) — except `sandbox`,
#    which fails closed (`[[ "$sandbox" != "0" ]]`).
#  * A `func` answering a value and a non-zero rc ends `kk._return V; return N`.
#  * `${inst}_argv` is rebuilt through a nameref.
#  * A CALLBACK that assigns a bare `expr=`, `quiet=`, `sandbox=0` or `inPlace=`
#    writes the INSTANCE's property (dynamic scoping) — callbacks declare
#    `local`.
# ---------------------------------------------------------------------------
class TSed : TUtil
    public
        var expr            # the FIRST expression (-e); '' = none
        var scriptFile      # -f FILE ('' = off), after the expressions
        var extended        # -E
        var quiet           # -n
        var separate        # -s   (implied by -i)
        var nullData        # -z  -> derives the sinks' -0 AND -b
        var binary          # -b  (keep the CR; also derived)
        var sandbox         # --sandbox, DEFAULT 1 (owner Q1); off ONLY for exactly '0'
        var inPlace         # -i  (derives -b; the sinks refuse it)
        var backupSuffix    # -iSUFFIX (only with inPlace = 1)
        var _nulDerived     # private bookkeeping for the -z -> -0 derivation
        constructor Create  # [EXPR [PATH...]]
        destructor  Destroy # frees ${inst}_paths, _exprs, _rfrom, _rto, _rflags, then inherited
        proc paths          # PATH... — REPLACES the operand list
        proc addExpr        # EXPR... — appended after `expr`; '' is a real element
        proc addReplace     # FROM TO [FLAGS] — a LITERAL s///, escaped at build time
        proc clearExprs     # empties the list (not `expr`)
        override func buildArgv
        override func mapRc
        override proc each
        override func toArray
        override func toList
        override func first
        override func count
        static proc edit    # EXPR PATH... — `sed --sandbox -e EXPR -- PATH...`
        static proc quoteRe       # TEXT [ere] — RESULT: TEXT as a literal regex
        static proc quoteRepl     # TEXT — RESULT: TEXT as a literal replacement
        static proc replace       # FROM TO PATH... — literal, every occurrence, to stdout
        static proc replaceInFile # FROM TO PATH... — the same, in place, no backup
end

# ===========================================================================
# Internal helpers (plain functions, never class members)
# ===========================================================================

# tsed._denied WORD — rc 0 when WORD is, to sed's getopt, one of the options
# this wrapper models as a typed property (the owner's Q6 deny-list). On rc 0 it
# sets the CALLER's `__tsd_dopt` (the option as sed reads it) and `__tsd_dprop`
# (the property to use instead); the caller declares both.
#
# The scan follows getopt, because that is what decides what sed does:
#   * a long word `--NAME[=VALUE]` is refused when NAME is a (possibly
#     abbreviated) prefix of a denied long option — measured on sed 4.9,
#     `--in=.bak` edits the file in place with rc 0, `--expr=p`, `--null` and
#     `--d` all work, and `--zero-terminated` is an undocumented alias of `-z`;
#   * a short word `-XYZ` is a bundle: each letter is an option until one that
#     takes an argument, so `-ni` is `-n -i`, `-i.bak` is `-i` with the suffix
#     attached, `-es/a/b/` is `-e` with its script attached. `l` (`-l N`) is the
#     one ALLOWED option that takes an argument: the scan stops there, so
#     `-ul40` passes;
#   * `-` alone and a word that is not an option pass here; `--` alone is
#     refused by `buildArgv` itself, with its own message.
tsed._denied() {
    local __tsd_w="${1:-}" __tsd_nm='' __tsd_l='' __tsd_c='' __tsd_k=0
    case "$__tsd_w" in
        --|-|'')
            return 1
            ;;
        --*)
            __tsd_nm="${__tsd_w#--}"
            __tsd_nm="${__tsd_nm%%=*}"
            if [[ -z "$__tsd_nm" ]]; then
                return 1
            fi
            for __tsd_l in in-place:inPlace null-data:nullData zero-terminated:nullData \
                           expression:expr file:scriptFile quiet:quiet silent:quiet \
                           separate:separate regexp-extended:extended binary:binary \
                           sandbox:sandbox; do
                if [[ "${__tsd_l%%:*}" == "$__tsd_nm"* ]]; then
                    __tsd_dopt="--${__tsd_l%%:*}"
                    __tsd_dprop="${__tsd_l#*:}"
                    return 0
                fi
            done
            return 1
            ;;
        -*)
            for (( __tsd_k = 1; __tsd_k < ${#__tsd_w}; __tsd_k++ )); do
                __tsd_c="${__tsd_w:__tsd_k:1}"
                case "$__tsd_c" in
                    i)   __tsd_dprop=inPlace ;;
                    z)   __tsd_dprop=nullData ;;
                    e)   __tsd_dprop=expr ;;
                    f)   __tsd_dprop=scriptFile ;;
                    n)   __tsd_dprop=quiet ;;
                    s)   __tsd_dprop=separate ;;
                    E|r) __tsd_dprop=extended ;;
                    b)   __tsd_dprop=binary ;;
                    l)   return 1 ;;
                    *)   continue ;;
                esac
                __tsd_dopt="-$__tsd_c"
                return 0
            done
            return 1
            ;;
    esac
    return 1
}

# tsed._isDebug WORD — rc 0 when sed's getopt reads WORD as `--debug` (any
# unambiguous prefix down to `--d`, with or without `=VALUE`).
tsed._isDebug() {
    local __tsd_nm=''
    case "${1:-}" in
        --?*)
            __tsd_nm="${1#--}"
            __tsd_nm="${__tsd_nm%%=*}"
            if [[ -n "$__tsd_nm" && "debug" == "$__tsd_nm"* ]]; then
                return 0
            fi
            ;;
    esac
    return 1
}

# tsed._sinkRefused SINK — the refusal every overridden sink runs FIRST (PLAN
# §2.4). rc 0 = refused (one kk.debug line already written; the caller answers
# rc 2 and runs nothing); rc 1 = go ahead. It reads the member frame's
# `$inPlace` and `$__inst__` through dynamic scoping, as `tutil._prep` does.
tsed._sinkRefused() {
    local __tsd_m="${1:-}"
    if [[ "$inPlace" == 1 ]]; then
        kk.debug "Error: TSed.$__tsd_m: in-place editing writes nothing to stdout; use run"
        return 0
    fi
    local -n __tsd_ea="${__inst__}_args"
    local __tsd_w
    for __tsd_w in "${__tsd_ea[@]}"; do
        if tsed._isDebug "$__tsd_w"; then
            kk.debug "Error: TSed.$__tsd_m: sed --debug writes to stdout; use run"
            return 0
        fi
    done
    return 1
}

# tsed._ret VALUE [RC] — kcl README §1.1's static-unit helper (the `tpath._ret`
# shape): RESULT = VALUE, printed only inside a subshell, so a direct call is
# silent and `$( )` prints the value exactly once.
tsed._ret() {
    RESULT="$1"
    if (( BASH_SUBSHELL > 0 )); then
        printf '%s' "$1"
    fi
    return "${2:-0}"
}

# tsed._qre TEXT ERE — TEXT as a literal regex for an `s/…/` with `/` as the
# delimiter (HELPERS_PLAN §2.1). Sets the CALLER's `__tsd_q`. BRE escapes
# `\ / . * [ ^ $`; ERE = the exact string `1` adds `+ ? ( ) { } |`; a newline
# becomes `\n`. The BACKSLASH goes FIRST — every later step introduces
# backslashes — and the newline LAST, for the same reason. One escape step is
# `${s//"$c"/"$bs$c"}`: both sides quoted, so the pattern is literal and the
# replacement is literal whatever `patsub_replacement` says. The newline is
# made with `printf -v` (no `$'…'` control character in this unit).
tsed._qre() {
    local __tsd_t="${1:-}" __tsd_c='' __tsd_bs='\' __tsd_n=''
    printf -v __tsd_n '\n'
    __tsd_t="${__tsd_t//"$__tsd_bs"/"$__tsd_bs$__tsd_bs"}"
    for __tsd_c in / . '*' '[' '^' '$'; do
        __tsd_t="${__tsd_t//"$__tsd_c"/"$__tsd_bs$__tsd_c"}"
    done
    if [[ "${2:-}" == 1 ]]; then
        for __tsd_c in '+' '?' '(' ')' '{' '}' '|'; do
            __tsd_t="${__tsd_t//"$__tsd_c"/"$__tsd_bs$__tsd_c"}"
        done
    fi
    __tsd_t="${__tsd_t//"$__tsd_n"/"${__tsd_bs}n"}"
    __tsd_q="$__tsd_t"
    return 0
}

# tsed._qrepl TEXT — TEXT as a literal `s///` replacement. Sets the CALLER's
# `__tsd_q`: escapes `\ / &`, a newline becomes `\` + newline (sed's spelling
# of a newline in the replacement). Backslash first, newline last.
tsed._qrepl() {
    local __tsd_t="${1:-}" __tsd_c='' __tsd_bs='\' __tsd_n=''
    printf -v __tsd_n '\n'
    __tsd_t="${__tsd_t//"$__tsd_bs"/"$__tsd_bs$__tsd_bs"}"
    for __tsd_c in / '&'; do
        __tsd_t="${__tsd_t//"$__tsd_c"/"$__tsd_bs$__tsd_c"}"
    done
    __tsd_t="${__tsd_t//"$__tsd_n"/"$__tsd_bs$__tsd_n"}"
    __tsd_q="$__tsd_t"
    return 0
}

# tsed._rflags FLAGS — the `s///` flags for an `addReplace` FLAGS string, the
# TStringHelper tokens split on `[[:space:]]` (space, TAB, newline, …): `rfReplaceAll` ->
# `g`, `rfIgnoreCase` -> `I` (GNU), in that order. Sets the CALLER's `__tsd_q`
# (the flags) and `__tsd_fbad` (the first unknown word). rc 0, or rc 1 on an
# unknown word. No `IFS` and no here-string: a pure prefix walk. `I` folds
# non-ASCII (`é`/`É`, Cyrillic) only under a UTF-8 LC_CTYPE — under `C` it is
# ASCII-only (README §7a; the unit's self-heal sets C.UTF-8 only when the
# environment names no locale at all).
tsed._rflags() {
    local __tsd_r="${1:-}" __tsd_w='' __tsd_g='' __tsd_i=''
    __tsd_q=''
    while [[ -n "$__tsd_r" ]]; do
        __tsd_r="${__tsd_r#"${__tsd_r%%[![:space:]]*}"}"
        if [[ -z "$__tsd_r" ]]; then
            break
        fi
        __tsd_w="${__tsd_r%%[[:space:]]*}"
        __tsd_r="${__tsd_r#"$__tsd_w"}"
        case "$__tsd_w" in
            rfReplaceAll) __tsd_g=g ;;
            rfIgnoreCase) __tsd_i=I ;;
            *)
                __tsd_fbad="$__tsd_w"
                return 1
                ;;
        esac
    done
    __tsd_q="$__tsd_g$__tsd_i"
    return 0
}

# ===========================================================================
# Members
# ===========================================================================

# Create [EXPR [PATH...]] — PLAN §1.2, §2.1. EXPR becomes `expr`, every further
# argument a path. `parent.constructor sed` is spelled out, EVERY declared var
# is assigned (`sandbox` = 1, the owner's Q1 default), `tutil._gnu sed` resolves
# the tool into `cmd` (L3.4: no GNU sed = `cmd` '' and `_toolErr`, `.new` still
# succeeds; the first buildArgv answers rc 2), and the five per-instance
# arrays (`_paths`, `_exprs` and the three `addReplace` arrays) are real globals
# next to `${inst}_data`, released by the destructor.
TSed.Create() {
    parent.constructor sed
    tutil._gnu sed
    expr="${1:-}"
    scriptFile=''
    extended=0
    quiet=0
    separate=0
    nullData=0
    binary=0
    sandbox=1
    inPlace=0
    backupSuffix=''
    _nulDerived=0
    declare -ga "${__inst__}_paths=()"
    declare -ga "${__inst__}_exprs=()"
    declare -ga "${__inst__}_rfrom=()"
    declare -ga "${__inst__}_rto=()"
    declare -ga "${__inst__}_rflags=()"
    local -n __tsd_p="${__inst__}_paths"
    __tsd_p=( "${@:2}" )
    return 0
}

# Destroy — release this class's five arrays, then chain to TUtil.Destroy.
TSed.Destroy() {
    unset -v "${__inst__}_paths" "${__inst__}_exprs" \
             "${__inst__}_rfrom" "${__inst__}_rto" "${__inst__}_rflags"
    inherited
    return 0
}

# paths PATH... — REPLACE the operand list. No argument = the stdin form.
TSed.paths() {
    local -n __tsd_p="${__inst__}_paths"
    __tsd_p=( "$@" )
    return 0
}

# addExpr EXPR... — append to the expression list, emitted after `expr` in call
# order. An EMPTY argument is a real element: `-e ''` is sed's identity. Each
# element also gets '' in the three `addReplace` arrays, so the index of an
# element is the same in all four. The word `__tsd_r__` is RESERVED (the
# `addReplace` marker): an argument equal to it is rc 2 with one kk.debug line,
# and NOTHING of that call is appended.
TSed.addExpr() {
    local -n __tsd_x="${__inst__}_exprs"
    local -n __tsd_rf="${__inst__}_rfrom"
    local -n __tsd_rt="${__inst__}_rto"
    local -n __tsd_rg="${__inst__}_rflags"
    local __tsd_s
    for __tsd_s in "$@"; do
        if [[ "$__tsd_s" == "__tsd_r__" ]]; then
            kk.debug "Error: TSed.addExpr: '__tsd_r__' is a reserved word (the addReplace marker in \${inst}_exprs); nothing was appended"
            return 2
        fi
    done
    for __tsd_s in "$@"; do
        __tsd_x+=( "$__tsd_s" )
        __tsd_rf+=( '' )
        __tsd_rt+=( '' )
        __tsd_rg+=( '' )
    done
    return 0
}

# addReplace FROM TO [FLAGS] — append a LITERAL replacement (HELPERS_PLAN §2.1):
# the marker `__tsd_r__` in `_exprs`, FROM / TO / FLAGS RAW at the same index
# in `_rfrom` / `_rto` / `_rflags`. Nothing is escaped or checked here:
# `buildArgv` does both, because the escape depends on `extended`, which may be
# set after this call. FLAGS follows TStringHelper: no FLAGS argument = every
# occurrence, stored as `rfReplaceAll`; a FLAGS argument (even '') = only what
# it names. A missing TO is '' (the text is deleted), as in TStringHelper.
# The one check made HERE is the arity: MORE than three arguments is rc 2 with
# one kk.debug line and nothing appended — `addReplace a b rfReplaceAll
# rfIgnoreCase` (the flags unquoted) would otherwise lose `rfIgnoreCase`.
TSed.addReplace() {
    if (( $# > 3 )); then
        kk.debug "Error: TSed.addReplace: usage: addReplace FROM TO [FLAGS] — got $# arguments; quote several flags as ONE word ('rfReplaceAll rfIgnoreCase'); nothing was appended"
        return 2
    fi
    local -n __tsd_x="${__inst__}_exprs"
    local -n __tsd_rf="${__inst__}_rfrom"
    local -n __tsd_rt="${__inst__}_rto"
    local -n __tsd_rg="${__inst__}_rflags"
    local __tsd_f=rfReplaceAll
    if (( $# >= 3 )); then
        __tsd_f="$3"
    fi
    __tsd_x+=( __tsd_r__ )
    __tsd_rf+=( "${1:-}" )
    __tsd_rt+=( "${2:-}" )
    __tsd_rg+=( "$__tsd_f" )
    return 0
}

# clearExprs — empty the list and the three `addReplace` arrays. `expr` is a
# property and is left alone.
TSed.clearExprs() {
    local -n __tsd_x="${__inst__}_exprs"
    local -n __tsd_rf="${__inst__}_rfrom"
    local -n __tsd_rt="${__inst__}_rto"
    local -n __tsd_rg="${__inst__}_rflags"
    __tsd_x=()
    __tsd_rf=()
    __tsd_rt=()
    __tsd_rg=()
    return 0
}

# buildArgv — the override, and the single truth about what will run. RESULT =
# the number of words, rc 0; on a refusal `kk._return ""`, rc 2, one kk.debug
# line, `${inst}_argv` left EMPTY.
TSed.buildArgv() {
    local -n __tsd_v="${__inst__}_argv"
    local -n __tsd_p="${__inst__}_paths"
    local -n __tsd_x="${__inst__}_exprs"
    local -n __tsd_a="${__inst__}_args"
    __tsd_v=()

    # ---- the rc 2 list, checked before a single word is built -------------
    if [[ -z "$cmd" ]]; then
        kk.debug "Error: TSed.buildArgv: ${_toolErr:-cmd is empty; there is nothing to run}"
        kk._return ""
        return 2
    fi
    if [[ -z "$expr" && -z "$scriptFile" ]] && (( ${#__tsd_x[@]} == 0 )); then
        kk.debug "Error: TSed.buildArgv: no script — expr is '', the addExpr list is empty and scriptFile is ''; sed would read the first path AS the script (the identity is addExpr '')"
        kk._return ""
        return 2
    fi
    local __tsd_s
    if [[ "$inPlace" == 1 ]]; then
        if (( ${#__tsd_p[@]} == 0 )); then
            kk.debug "Error: TSed.buildArgv: inPlace = 1 with no path; sed -i has no stdin form — give the file(s) to edit"
            kk._return ""
            return 2
        fi
        for __tsd_s in "${__tsd_p[@]}"; do
            if [[ "$__tsd_s" == "-" ]]; then
                kk.debug "Error: TSed.buildArgv: inPlace = 1 with the path '-'; sed cannot edit stdin in place"
                kk._return ""
                return 2
            fi
        done
    fi
    if [[ -n "$backupSuffix" && "$inPlace" != 1 ]]; then
        kk.debug "Error: TSed.buildArgv: backupSuffix '$backupSuffix' with inPlace = 0; the suffix only means something to -i — set inPlace = 1 or clear backupSuffix"
        kk._return ""
        return 2
    fi
    if [[ "$backupSuffix" == "*" ]]; then
        kk.debug "Error: TSed.buildArgv: backupSuffix '*' names the backup exactly like the file, so sed makes NO backup, silently — use e.g. '.bak' or 'bak_*'"
        kk._return ""
        return 2
    fi
    local __tsd_dopt='' __tsd_dprop='' __tsd_w
    for __tsd_w in "${__tsd_a[@]}"; do
        # `--` among the extras ends sed's options before the first `-e`:
        # measured, `addArg --` built `sed --sandbox -- -e s/a/A/ -- f`, and
        # every expression became an OPERAND (sed then read `-e` as its script).
        if [[ "$__tsd_w" == "--" ]]; then
            kk.debug "Error: TSed.buildArgv: the extra '--' ends sed's options, so every expression after it would become an operand; the wrapper emits its own '--' before the paths"
            kk._return ""
            return 2
        fi
        if tsed._denied "$__tsd_w"; then
            if [[ "$__tsd_dprop" == "expr" ]]; then
                __tsd_dprop="expr / addExpr"
            fi
            kk.debug "Error: TSed.buildArgv: the extra '$__tsd_w' is sed's $__tsd_dopt, which this wrapper models as the property '$__tsd_dprop' — use the property, not addArg (an extra would break the pinned argv order or the sinks' refusals)"
            kk._return ""
            return 2
        fi
    done

    # ---- the `addReplace` elements (HELPERS_PLAN §2.1-§2.2) ----------------
    # Each element of `_exprs` becomes one `-e` word in `__tsd_ex`: an
    # `addExpr` element verbatim, an `addReplace` element (the marker) built
    # HERE from the raw data, so the dialect is the one `extended` holds NOW.
    local -n __tsd_rf="${__inst__}_rfrom"
    local -n __tsd_rt="${__inst__}_rto"
    local -n __tsd_rg="${__inst__}_rflags"
    local -a __tsd_ex=()
    local __tsd_k=0 __tsd_q='' __tsd_fl='' __tsd_fbad='' __tsd_ere=0 __tsd_from='' __tsd_lf=''
    if [[ "$extended" == 1 ]]; then
        __tsd_ere=1
    fi
    printf -v __tsd_lf '\n'
    for (( __tsd_k = 0; __tsd_k < ${#__tsd_x[@]}; __tsd_k++ )); do
        if [[ "${__tsd_x[__tsd_k]}" != "__tsd_r__" ]]; then
            __tsd_ex+=( "${__tsd_x[__tsd_k]}" )
            continue
        fi
        __tsd_from="${__tsd_rf[__tsd_k]:-}"
        if [[ -z "$__tsd_from" ]]; then
            kk.debug "Error: TSed.buildArgv: addReplace with an empty FROM; sed would reuse the previous regex — give the text to replace"
            kk._return ""
            return 2
        fi
        if [[ "$__tsd_from" == *"$__tsd_lf"* && "$nullData" != 1 ]]; then
            kk.debug "Error: TSed.buildArgv: addReplace FROM holds a newline while nullData is not 1; a line never contains one, so it could never match — set nullData = 1"
            kk._return ""
            return 2
        fi
        if ! tsed._rflags "${__tsd_rg[__tsd_k]:-}"; then
            kk.debug "Error: TSed.buildArgv: addReplace flag '$__tsd_fbad' is not a known token — use rfReplaceAll, rfIgnoreCase (no FLAGS = every occurrence)"
            kk._return ""
            return 2
        fi
        __tsd_fl="$__tsd_q"
        tsed._qre "$__tsd_from" "$__tsd_ere"
        __tsd_s="s/$__tsd_q/"
        tsed._qrepl "${__tsd_rt[__tsd_k]:-}"
        __tsd_ex+=( "$__tsd_s$__tsd_q/$__tsd_fl" )
    done

    # ---- the -z -> -0 derivation (PLAN §2.3, tgrep's P3-F1 guard) ----------
    # `_nulDerived` records that WE set `nul`: turning `nullData` back off takes
    # the `-0` off again, while a `nul = 1` the CALLER set is never touched.
    if [[ "$nullData" == 1 ]]; then
        if [[ "$nul" != 1 ]]; then
            nul=1
            _nulDerived=1
        fi
    elif [[ "$_nulDerived" == 1 ]]; then
        nul=0
        _nulDerived=0
    fi

    # ---- the CR contract (tutil README §3, owner DL11) ---------------------
    # Text mode = no `-b` (binary, inPlace and nullData all off). cygwin/msys
    # sed drops the line-end CR on input itself; elsewhere (`tutil._keepsCr`)
    # the SCRIPT is preceded by a prelude, so it never sees that CR either:
    #
    #     -e 's/<CR>$//' -e 't__tsd_cr' -e ':__tsd_cr'
    #
    # The `t` jump resets sed's "a substitution was made" flag that the prelude
    # `s` just set — without it the script's own first `t` would branch on our
    # substitution. The label `__tsd_cr` is reserved (README §5). A script whose
    # first line is exactly `#n` (from `expr`, else the first `addExpr`, else
    # line 1 of `scriptFile`) means `-n` to sed only when it is the script's
    # FIRST line, which the prelude takes away — so the build adds `-n` itself.
    # Nothing goes to TUtil's output strip: a CR the script writes on purpose
    # (`s/$/\r/`) is kept on every platform. `_textMode` stays 0 for TSed.
    _textMode=0
    local __tsd_pre=0 __tsd_hn=0 __tsd_first='' __tsd_nl=''
    if [[ "$binary" != 1 && "$inPlace" != 1 && "$nullData" != 1 ]] && tutil._keepsCr; then
        __tsd_pre=1
        printf -v __tsd_nl '\n'
        if [[ -n "$expr" ]]; then
            __tsd_first="${expr%%"$__tsd_nl"*}"
        elif (( ${#__tsd_ex[@]} > 0 )); then
            __tsd_first="${__tsd_ex[0]%%"$__tsd_nl"*}"
        elif [[ -n "$scriptFile" && -r "$scriptFile" ]]; then
            IFS= read -r __tsd_first < "$scriptFile" || true
        fi
        if [[ "$__tsd_first" == "#n" && "$quiet" != 1 ]]; then
            __tsd_hn=1
        fi
    fi

    # ---- the argv, in the pinned order: every option before the first -e --
    __tsd_v=( "$cmd" )
    # `sandbox` FAILS CLOSED — the one deliberate exception to the family
    # boolean rule (every other flag is on only for the exact string `1`).
    # Owner Q1 made the sandbox a security default, so `--sandbox` is dropped
    # ONLY for the exact string `0`; '', `yes`, `2`, ` 0`, `00` all keep it.
    if [[ "$sandbox" != "0" ]]; then __tsd_v+=( --sandbox ); fi
    if [[ "$extended" == 1 ]]; then __tsd_v+=( -E ); fi
    if [[ "$quiet"    == 1 || "$__tsd_hn" == 1 ]]; then __tsd_v+=( -n ); fi
    if [[ "$separate" == 1 ]]; then __tsd_v+=( -s ); fi
    if [[ "$nullData" == 1 ]]; then __tsd_v+=( -z ); fi
    # Owner Q5: the derived -b. Nothing is written back to `binary`. Without
    # it the build is TEXT mode (the CR contract above).
    if [[ "$binary" == 1 || "$inPlace" == 1 || "$nullData" == 1 ]]; then
        __tsd_v+=( -b )
    fi
    if [[ "$inPlace" == 1 ]]; then __tsd_v+=( "-i$backupSuffix" ); fi
    if (( ${#__tsd_a[@]} > 0 )); then __tsd_v+=( "${__tsd_a[@]}" ); fi
    if [[ "$__tsd_pre" == 1 ]]; then
        __tsd_v+=( -e "$__TUTIL_CR_SED" -e 't__tsd_cr' -e ':__tsd_cr' )
    fi
    if [[ -n "$expr" ]]; then __tsd_v+=( -e "$expr" ); fi
    for __tsd_s in "${__tsd_ex[@]}"; do
        __tsd_v+=( -e "$__tsd_s" )
    done
    if [[ -n "$scriptFile" ]]; then __tsd_v+=( -f "$scriptFile" ); fi
    if (( ${#__tsd_p[@]} > 0 )); then __tsd_v+=( -- "${__tsd_p[@]}" ); fi

    kk._return "${#__tsd_v[@]}"
    return 0
}

# mapRc RAW — owner Q3. sed's own statuses are 1 (a bad script), 2 (a missing
# input file; the other files are still processed) and 4 (an I/O error;
# processing STOPS at that operand). A script's `q N`/`Q N` exits with N mod
# 256, so `q1`/`q2`/`q4` are indistinguishable from those — the line says so.
# Any other non-zero status can only be the script's and is NOT an error: rc 1,
# silent, the raw value in `lastRc`.
TSed.mapRc() {
    local __tsd_raw="${1:-}"
    case "$__tsd_raw" in
        0)
            kk._return "0"
            return 0
            ;;
        127)
            kk.debug "Error: TSed.mapRc: command not found (raw rc 127)"
            ;;
        1|2|4)
            kk.debug "Error: TSed.mapRc: sed exited $__tsd_raw (a sed error, or the script's q/Q $__tsd_raw)"
            ;;
    esac
    kk._return "1"
    return 0
}

# ---------------------------------------------------------------------------
# The five sinks (PLAN §2.4). Each runs `tsed._sinkRefused` FIRST, then the base
# sink through the rc-PRESERVING spelling: `build` compiles a
# `kk._return "$RESULT"` trailer onto a `func`, so a body that merely ENDS on
# `inherited X "$@"` would answer rc 0 where the base answered 1. The funcs
# capture the rc, save RESULT at once and re-raise both; the proc `each` has no
# return channel and re-raises the rc alone.
# ---------------------------------------------------------------------------

TSed.each() {
    if tsed._sinkRefused each; then
        return 2
    fi
    local __tsd_rc=0
    inherited each "$@" || __tsd_rc=$?
    return "$__tsd_rc"
}

TSed.toArray() {
    if tsed._sinkRefused toArray; then
        kk._return ""
        return 2
    fi
    local __tsd_rc=0
    inherited toArray "$@" || __tsd_rc=$?
    local __tsd_n="$RESULT"
    kk._return "$__tsd_n"
    return "$__tsd_rc"
}

TSed.toList() {
    if tsed._sinkRefused toList; then
        kk._return ""
        return 2
    fi
    local __tsd_rc=0
    inherited toList "$@" || __tsd_rc=$?
    local __tsd_n="$RESULT"
    kk._return "$__tsd_n"
    return "$__tsd_rc"
}

TSed.first() {
    if tsed._sinkRefused first; then
        kk._return ""
        return 2
    fi
    local __tsd_rc=0
    inherited first "$@" || __tsd_rc=$?
    local __tsd_n="$RESULT"
    kk._return "$__tsd_n"
    return "$__tsd_rc"
}

TSed.count() {
    if tsed._sinkRefused count; then
        kk._return ""
        return 2
    fi
    local __tsd_rc=0
    inherited count "$@" || __tsd_rc=$?
    local __tsd_n="$RESULT"
    kk._return "$__tsd_n"
    return "$__tsd_rc"
}

# edit EXPR PATH... — the one-liner (PLAN §2.7): `sed --sandbox -e EXPR --
# PATH...` as a STREAM, with the rc mapped. A `static proc`: it prints sed's
# stdout and never calls `kk._return`.
#
# The throw-away instance is built with an EMPTY `expr` and then
# `addExpr "$EXPR"`, so an empty EXPR is a real `-e ''` — the identity — and not
# "no script". The sandbox is forced on (the default, and there is no way to
# turn it off from here). At least ONE path is required: with none sed would
# read the caller's stdin — rc 2, nothing runs. The reserved EXPR `__tsd_r__`
# is `addExpr`'s rc 2 (its one line), passed straight back, nothing run.
TSed.edit() {
    if (( $# < 2 )); then
        kk.debug "Error: TSed.edit: usage: TSed.edit EXPR PATH... — at least one path is required (with none sed would read the caller's stdin); build an instance for the stdin form"
        return 2
    fi
    __TSD_SEQ=$(( __TSD_SEQ + 1 ))
    local __tsd_i="__tsd_e_${BASHPID}_${__TSD_SEQ}"
    TSed.new "$__tsd_i" '' "${@:2}"
    local __tsd_rc=0
    "$__tsd_i".addExpr "$1" || __tsd_rc=$?
    if [[ "$__tsd_rc" != 0 ]]; then
        "$__tsd_i".delete
        return "$__tsd_rc"
    fi
    "$__tsd_i".sandbox = 1
    "$__tsd_i".run || __tsd_rc=$?
    "$__tsd_i".delete
    return "$__tsd_rc"
}

# quoteRe TEXT [ere] — TEXT as a literal regex for `s/…/` (HELPERS_PLAN §2.1):
# BRE escapes `\ / . * [ ^ $`; with the second argument EXACTLY `ere` also
# `+ ? ( ) { } |`; a newline becomes `\n`. ANY other second argument (`ERE`,
# `-E`, `1`, '' given) is rc 2 with one kk.debug line and RESULT '' — it fails
# CLOSED: a BRE escape fed to `sed -E` would leave `( ) { } | + ?` live.
# A `static proc` answering in RESULT (kcl README §1.1): a direct call prints
# nothing, `$( )` prints the value exactly once. A static has no instance, so
# the dialect is an argument; `addReplace` follows `extended` instead.
TSed.quoteRe() {
    local __tsd_q='' __tsd_e=0
    if (( $# >= 2 )); then
        if [[ "$2" != "ere" ]]; then
            kk.debug "Error: TSed.quoteRe: usage: TSed.quoteRe TEXT [ere] — the dialect word is exactly 'ere' (or absent for BRE), got '$2'"
            tsed._ret '' 2
            return 2
        fi
        __tsd_e=1
    fi
    tsed._qre "${1:-}" "$__tsd_e"
    tsed._ret "$__tsd_q"
}

# quoteRepl TEXT — TEXT as a literal `s///` replacement: escapes `\ / &`; a
# newline becomes `\` + newline. RESULT, as `quoteRe`.
TSed.quoteRepl() {
    local __tsd_q=''
    tsed._qrepl "${1:-}"
    tsed._ret "$__tsd_q"
}

# replace FROM TO PATH... — replace the LITERAL text FROM by the literal TO,
# every occurrence, and STREAM the result (HELPERS_PLAN §2.1). Built exactly
# like `edit`: a throw-away instance `__tsd_e_${BASHPID}_${__TSD_SEQ}`, one
# `addReplace FROM TO`, the sandbox forced, `run`, `delete`. It prints sed's
# stdout and never calls `kk._return`; it never edits in place
# (`replaceInFile` does). At least ONE path: with none sed would read the
# caller's stdin — rc 2, nothing runs. An empty FROM, or a FROM holding a
# newline, is `buildArgv`'s rc 2.
TSed.replace() {
    if (( $# < 3 )); then
        kk.debug "Error: TSed.replace: usage: TSed.replace FROM TO PATH... — at least one path is required (with none sed would read the caller's stdin); build an instance with addReplace for the stdin form"
        return 2
    fi
    __TSD_SEQ=$(( __TSD_SEQ + 1 ))
    local __tsd_i="__tsd_e_${BASHPID}_${__TSD_SEQ}"
    TSed.new "$__tsd_i" '' "${@:3}"
    "$__tsd_i".addReplace "$1" "$2"
    "$__tsd_i".sandbox = 1
    local __tsd_rc=0
    "$__tsd_i".run || __tsd_rc=$?
    "$__tsd_i".delete
    return "$__tsd_rc"
}

# replaceInFile FROM TO PATH... — `replace`, IN PLACE (`inPlace = 1`, the
# derived `-b` keeps every CR on disk), NO backup (HELPERS_PLAN D3; build an
# instance with `backupSuffix` for one). sed rewrites every file even with zero
# matches (the mtime changes). Same guards as `replace`; the path `-` is
# `buildArgv`'s in-place rc 2.
TSed.replaceInFile() {
    if (( $# < 3 )); then
        kk.debug "Error: TSed.replaceInFile: usage: TSed.replaceInFile FROM TO PATH... — at least one path is required (sed -i has no stdin form)"
        return 2
    fi
    __TSD_SEQ=$(( __TSD_SEQ + 1 ))
    local __tsd_i="__tsd_e_${BASHPID}_${__TSD_SEQ}"
    TSed.new "$__tsd_i" '' "${@:3}"
    "$__tsd_i".addReplace "$1" "$2"
    "$__tsd_i".sandbox = 1
    "$__tsd_i".inPlace = 1
    local __tsd_rc=0
    "$__tsd_i".run || __tsd_rc=$?
    "$__tsd_i".delete
    return "$__tsd_rc"
}

# Finalize: extract the bodies above into the `TSed` class and generate the
# per-instance wrappers.
build TSed
