#!/bin/bash

# ===========================================================================
# tregex — a bash port of Delphi System.RegularExpressions.TRegEx
#          (kcl static class over the bash [[ =~ ]] ERE engine).
#
# Source of truth: Delphi DocWiki TRegEx (record of static class functions);
# .NET Regex documented behavior breaks ties. FPC packages/regexpr (TRegExpr,
# Sorokin engine) is reference-only — its API is non-standard and its engine
# is NOT ported. Plan/ledger: kcl/tregex/PLAN.md, kcl/tregex/tregex_ledger.json.
#
# ---- The load-bearing decision: API is TRegEx, ENGINE is [[ =~ ]] ----------
# The regex engine is the bash builtin `[[ $s =~ $re ]]` — POSIX ERE via
# glibc regexec, C-speed, fork-free, internally caching compiled patterns.
# A bash-implemented engine would be ~100x slower and thousands of lines.
# The price is honesty about the DIALECT: ERE is not PCRE. Every divergence
# is documented (README delta table) AND pinned by a test — never silently
# emulated. wontfix set: lazy quantifiers, lookaround, named groups, pattern
# backrefs, \d\w\s guarantees (use POSIX classes), inline (?i)/(?x), multiline
# ^/$, PCRE leftmost-FIRST alternation (ERE is leftmost-LONGEST).
#
# ---- P0 probe findings (S1-S12, both bash 5.2.37 AND 5.3.9, 2026-07-12) ----
# The two bashes are SEMANTICALLY IDENTICAL on every probe (rc, matched text,
# offsets, group participation, word boundaries, leftmost-longest). The ONE
# difference: 5.3.9 prints a diagnostic to STDERR on an invalid/empty pattern
# (rc=2 on both); 5.2.37 is silent. Hence every user-pattern match redirects
# stderr:  [[ $text =~ $__re ]] 2>/dev/null  — probed to (a) suppress the 5.3
# diagnostic, (b) preserve rc=2, (c) stay FORK-FREE (redirect on the [[ ]]
# keyword does not spawn a subshell). Pinned facts:
#   S1  '.' MATCHES newline (subject is one string; PCRE default differs).
#   S2  empty pattern '' -> rc=2 (INVALID on this engine; not match-all).
#   S3  invalid pattern  -> rc=2 (distinct from rc=1 no-match).
#   S4  nocasematch affects =~ (and ==); `shopt -q` is a fork-free query.
#   S5  offset recovery via prefix-strip is EXACT for unanchored patterns.
#   S6  offset recovery is a documented CAVEAT for ^ $ \b \< \> anchored
#       patterns whose matched TEXT recurs earlier (prefix-strip finds the
#       earlier copy). Global scans advance by STRING ops, so match
#       CORRECTNESS is unaffected — only the reported numeric index.
#   S7  \b \< \> word boundaries work on BOTH bashes (GNU/glibc; not POSIX).
#   S8  alternation is leftmost-LONGEST: (a|ab) on "ab" -> "ab" (PCRE: "a").
#   S9  offsets/lengths are `${#...}` in the AMBIENT locale. ASCII exact.
#       Multibyte: under empty/C locale on MSYS2 `${#}` byte-counts while the
#       regex engine char-counts -> they disagree; a full UTF-8 locale
#       (C.UTF-8/en_US.UTF-8) makes both char-count. Documented; correctness
#       of scans is locale-independent (string-op advance).
#   S10 non-participating group in alternation -> EMPTY STRING, array dense
#       (indistinguishable from an empty match; documented). Same on 5.2/5.3.
#   S11 replacement grammar $0..$9 / $$ / literal-unknown-$x — pure-bash
#       assembly (sed metachars & \ are LITERAL); pinned in P3.
#   S12 split keeps captured groups and empty pieces (.NET pin); P2.
#   ADJ a FAILED [[ =~ ]] CLEARS BASH_REMATCH (nelem 0) on both bashes, so
#       BASH_REMATCH must be COPIED immediately after a successful match,
#       before any other [[ =~ ]].
#
# ---- Return contract (RESULT globals, DIRECT call; kcl house style) --------
# Members are `static proc`s. PINNED at P0 from a both-bash probe: for a kklass
# STATIC class the two member kinds differ on the echo axis —
#   * `static func`  ECHOES $RESULT on EVERY call (direct too), not just under
#                    $(). That pollutes stdout for rc-drivers (e.g. isMatch in
#                    `if TRegEx.isMatch ...`) and can only carry ONE of match's
#                    four return values.
#   * `static proc`  is SILENT and sets the RESULT* globals. UNIFORM, no
#                    surprises. (Instance `func`, as in tstopwatch, echoes only
#                    under $() — but static `func` is NOT the same; hence proc.)
# So the contract is: CALL DIRECTLY, then read the globals —
#   RESULT         primary scalar (matched text | result string | count)
#   RESULT_INDEX   0-based offset of the match (prefix-strip; S5/S6 caveat)
#   RESULT_LENGTH  ${#matchedtext} in the ambient locale
#   RESULT_GROUPS  copy of BASH_REMATCH[1..] (numbered groups; S10)
# For the multi-value / rc / array members (match, matches, split, isMatch) do
# NOT use $() capture: it runs in a SUBSHELL, so every RESULT* global and any
# nameref array fill is LOST to the parent (same caveat tstopwatch/tdictionary
# document). Call them DIRECTLY:
#   TRegEx.match "$s" "$re"; use $RESULT $RESULT_INDEX "${RESULT_GROUPS[@]}"
#   if TRegEx.isMatch "$s" "$re"; then ...
# The single-scalar string members (escape, replace, replaceCb) ADDITIONALLY
# body-echo their one return value (owner-approved P1), so $() is ergonomic:
#   safe=$(TRegEx.escape "$u")        out=$(TRegEx.replace "$s" "$re" "$rep")
# (they also set RESULT, so a direct call + $RESULT works too).
# i-FLAG (case-insensitive): case sensitivity is decided SOLELY by the flag
# (Delphi roIgnoreCase is per-call), so the match FORCES nocasematch on/off and
# RESTORES the caller's ambient shopt after — deterministic regardless of the
# caller's global `shopt nocasematch`; fork-free (no $()).
# rc: 0 match / 1 no-match / 2 invalid pattern (debug msg under
# VERBOSE_KKLASS=debug; bash's own stderr is always suppressed).
# ===========================================================================

# Re-source guard: the class need only be built once per process; a second
# source is a clean no-op (returns BEFORE `build`, so the kklass duplicate-
# class guard never trips on a legitimate re-source).
if [[ -n "$_TREGEX_SOURCED" ]]; then
    return
fi
declare -g _TREGEX_SOURCED=1

# Source the kklass Pascal-style DSL front-end (don't override SCRIPT_DIR).
TREGEX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TREGEX_DIR/../../kklass/kklass_pascal.sh"

# ---------------------------------------------------------------------------
# Class surface (member types FINAL as of P0 — bodies filled per phase).
# All members are `static proc` (silent RESULT-globals contract, see above);
# the API is a flat static utility, no instances (§2.6: nothing to precompile
# — bash caches compiled patterns internally, so TRegEx.Create would be pure
# dispatch overhead; wontfix).
# ---------------------------------------------------------------------------
class TRegEx
    public
        static proc isMatch      # P1  isMatch text pattern [flags]        -> rc 0/1/2
        static proc match        # P1  match text pattern [flags]          -> RESULT*
        static proc escape       # P1  escape text                         -> RESULT
        static proc matches      # P2  matches text pattern outTexts [outOffsets|-] [flags]
        static proc split        # P2  split text pattern outArr [maxCount|-] [flags]
        static proc replace      # P3  replace text pattern repl [maxCount|-] [flags]  (echoes)
        static proc replaceCb    # P3  replaceCb text pattern cbName [maxCount|-] [flags]  (echoes)
end

# ---------------------------------------------------------------------------
# Internal core (plain function, NOT a class member): ONE match with i-flag
# handling — fork-free, ambient-shopt-safe. Dynamic-scope OUT params (the
# caller declares them local BEFORE calling; same idiom as tstopwatch._nowUs):
#   __tre_rc  0 match / 1 no-match / 2 invalid-pattern (bash's own =~ signal)
#   __tre_m   matched text (BASH_REMATCH[0]; empty on no-match/invalid)
#   __tre_g   array copy of BASH_REMATCH[@] (index 0 = whole match, 1.. groups)
# The pattern is ALWAYS bound through a local var (a quoted RHS matches
# literally; an inline (a|b) is a bash parse error — pinned kcl idiom). stderr
# is suppressed on the [[ ]] (bash 5.3 prints a diagnostic on an invalid
# pattern; rc=2 on BOTH bashes) — the redirect is fork-free (P0). BASH_REMATCH
# is copied IMMEDIATELY (any later [[ =~ ]], even one hidden in a helper,
# clobbers it; a FAILED match clears it — P0/ADJ).
# ---------------------------------------------------------------------------
TRegEx._match1() {
    local __re="$2" __flags="${3:-}" __had=0
    shopt -q nocasematch && __had=1
    if [[ "$__flags" == *i* ]]; then shopt -s nocasematch; else shopt -u nocasematch; fi
    [[ "$1" =~ $__re ]] 2>/dev/null
    __tre_rc=$?
    __tre_g=("${BASH_REMATCH[@]}")
    __tre_m="${BASH_REMATCH[0]}"
    if (( __had )); then shopt -s nocasematch; else shopt -u nocasematch; fi
    return 0
}

# Internal: debug-only note for an invalid pattern (rc=2). bash's native stderr
# is always suppressed; this speaks ONLY under VERBOSE_KKLASS=debug.
TRegEx._invalid() {
    [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && \
        echo "TRegEx.$1: invalid pattern (rc=2): '$2'" >&2
    return 0
}

# ---- P1 members ------------------------------------------------------------

# isMatch text pattern [flags]  ->  rc 0 match / 1 no-match / 2 invalid.
# Pure predicate: returns rc, writes NO RESULT* globals (use `match` for the
# payload). Silent. Idiom:  if TRegEx.isMatch "$s" "$re"; then ...
TRegEx.isMatch() {
    local __tre_rc __tre_m; local -a __tre_g
    TRegEx._match1 "$1" "$2" "${3:-}"
    (( __tre_rc == 2 )) && TRegEx._invalid isMatch "$2"
    return $__tre_rc
}

# match text pattern [flags]  ->  on match (rc 0):
#   RESULT        = matched text (BASH_REMATCH[0])
#   RESULT_INDEX  = 0-based offset via prefix-strip (exact unanchored; S6
#                   caveat for ^ $ \b \< \> whose match-text recurs earlier)
#   RESULT_LENGTH = ${#matched} in the ambient locale
#   RESULT_GROUPS = numbered groups (BASH_REMATCH[1..]; non-participating='' S10)
# On no-match (rc 1) / invalid (rc 2): RESULT='' INDEX=-1 LENGTH=0 GROUPS=().
# Silent — four values via globals, so call DIRECTLY (never $()-capture).
TRegEx.match() {
    local __tre_rc __tre_m; local -a __tre_g
    TRegEx._match1 "$1" "$2" "${3:-}"
    if (( __tre_rc == 0 )); then
        RESULT="$__tre_m"
        local __pre="${1%%"$__tre_m"*}"
        RESULT_INDEX=${#__pre}
        RESULT_LENGTH=${#__tre_m}
        RESULT_GROUPS=("${__tre_g[@]:1}")
    else
        (( __tre_rc == 2 )) && TRegEx._invalid match "$2"
        RESULT=""; RESULT_INDEX=-1; RESULT_LENGTH=0; RESULT_GROUPS=()
    fi
    return $__tre_rc
}

# escape text  ->  RESULT = text with every ERE metacharacter backslash-quoted,
# so the result matches `text` LITERALLY. Metaset: \ . ^ $ * + ? ( ) [ ] { } |
# (backslash needs no special ordering — the loop tests each INPUT char once,
# so nothing is double-escaped). Owner-approved P1: escape BODY-ECHOES its
# scalar for $() ergonomics AND sets RESULT. Fork-free pure char loop (no sed).
TRegEx.escape() {
    local __s="$1" __out="" __c __i __meta='\.^$*+?()[]{}|'
    for (( __i = 0; __i < ${#__s}; __i++ )); do
        __c="${__s:__i:1}"
        [[ "$__meta" == *"$__c"* ]] && __out+="\\"
        __out+="$__c"
    done
    RESULT="$__out"
    printf '%s\n' "$__out"
    return 0
}

# ---- P2 members: global scan (matches, split) ------------------------------
# Both scan leftmost-longest on the REMAINDER via _match1, advancing past each
# match; an EMPTY match advances by ONE char (PCRE/.NET rule — no infinite
# loop; an empty match at end-of-string is the last one). Both are SILENT and
# fill nameref arrays, so CALL THEM DIRECTLY — a $() subshell discards the
# fills. ANCHOR CAVEAT (documented delta): ^ $ \b \< \> are relative to the
# REMAINDER, not the whole string (bash cannot \G-anchor a scan) — unanchored
# patterns are exact, anchored ones re-anchor per remainder. Reserved local
# names: do not pass output arrays named __trx_texts / __trx_offs / __trx_out.

# matches text pattern outTexts [outOffsets|-] [flags]
#   RESULT = match count; fills outTexts (lossless). If arg 4 is a name (not ''
#   nor '-') it also fills outOffsets with 0-based absolute offsets (prefix-strip
#   units; S6 caveat under anchors). To pass flags WITHOUT offsets, use '-' for
#   arg 4. rc 0 (>=1 match) / 1 (none) / 2 (invalid pattern).
TRegEx.matches() {
    if [[ -z "$3" ]]; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "TRegEx.matches: outTexts array name required" >&2
        RESULT=0; return 2
    fi
    local -n __trx_texts="$3"; __trx_texts=()
    local __trx_have_off=0
    if [[ -n "${4:-}" && "$4" != "-" ]]; then
        local -n __trx_offs="$4"; __trx_offs=(); __trx_have_off=1
    fi
    local __trx_rem="$1" __trx_consumed=0 __trx_count=0 __trx_flags="${5:-}"
    local __tre_rc __tre_m; local -a __tre_g
    while : ; do
        TRegEx._match1 "$__trx_rem" "$2" "$__trx_flags"
        if (( __tre_rc == 2 )); then
            TRegEx._invalid matches "$2"; RESULT=0; return 2
        fi
        (( __tre_rc != 0 )) && break
        local __trx_m="$__tre_m" __trx_pre="${__trx_rem%%"$__tre_m"*}" __trx_loff
        __trx_loff=${#__trx_pre}
        __trx_texts+=("$__trx_m")
        (( __trx_have_off )) && __trx_offs+=( "$(( __trx_consumed + __trx_loff ))" )
        (( __trx_count++ ))
        local __trx_adv
        [[ -z "$__trx_m" ]] && __trx_adv=$(( __trx_loff + 1 )) || __trx_adv=$(( __trx_loff + ${#__trx_m} ))
        (( __trx_adv > ${#__trx_rem} )) && break
        __trx_rem="${__trx_rem:__trx_adv}"
        __trx_consumed=$(( __trx_consumed + __trx_adv ))
    done
    RESULT=$__trx_count
    (( __trx_count > 0 )) && return 0 || return 1
}

# split text pattern outArr [maxCount|-] [flags]
#   RESULT = piece count; fills outArr with the pieces BETWEEN matches (.NET
#   Regex.Split, S12): captured groups are INTERLEAVED, and leading/trailing/
#   consecutive empty pieces are KEPT. Assembled by ABSOLUTE position
#   text[prevEnd:matchStart], so empty-match patterns split correctly. No match
#   -> the whole text as a single piece. maxCount (arg 4, integer; 0/''/'-' =
#   unlimited) caps the piece count Delphi/Perl-style: after maxCount-1 splits
#   the scan stops and the ENTIRE remainder (delimiters and all) is the last
#   piece. To pass flags without a limit, use '-' (or 0) for arg 4. rc 0 / 2.
TRegEx.split() {
    if [[ -z "$3" ]]; then
        [[ "${VERBOSE_KKLASS:-}" == "debug" ]] && echo "TRegEx.split: outArr name required" >&2
        RESULT=0; return 2
    fi
    local -n __trx_out="$3"; __trx_out=()
    local __trx_limit="${4:-0}" __trx_flags="${5:-}"
    [[ "$__trx_limit" == "-" || -z "$__trx_limit" ]] && __trx_limit=0
    local __trx_text="$1" __trx_rem="$1" __trx_consumed=0 __trx_prevEnd=0 __trx_done=0
    local __tre_rc __tre_m; local -a __tre_g
    while : ; do
        TRegEx._match1 "$__trx_rem" "$2" "$__trx_flags"
        if (( __tre_rc == 2 )); then
            TRegEx._invalid split "$2"; __trx_out=(); RESULT=0; return 2
        fi
        (( __tre_rc != 0 )) && break
        (( __trx_limit > 0 && __trx_done >= __trx_limit - 1 )) && break
        local __trx_m="$__tre_m" __trx_pre="${__trx_rem%%"$__tre_m"*}" __trx_loff
        __trx_loff=${#__trx_pre}
        local __trx_p=$(( __trx_consumed + __trx_loff ))
        __trx_out+=( "${__trx_text:__trx_prevEnd:$(( __trx_p - __trx_prevEnd ))}" )
        local __trx_i
        for (( __trx_i = 1; __trx_i < ${#__tre_g[@]}; __trx_i++ )); do
            __trx_out+=( "${__tre_g[__trx_i]}" )
        done
        __trx_prevEnd=$(( __trx_p + ${#__trx_m} ))
        (( __trx_done++ ))
        local __trx_adv
        [[ -z "$__trx_m" ]] && __trx_adv=$(( __trx_loff + 1 )) || __trx_adv=$(( __trx_loff + ${#__trx_m} ))
        (( __trx_adv > ${#__trx_rem} )) && break
        __trx_rem="${__trx_rem:__trx_adv}"
        __trx_consumed=$(( __trx_consumed + __trx_adv ))
    done
    __trx_out+=( "${__trx_text:__trx_prevEnd}" )
    RESULT=${#__trx_out[@]}
    return 0
}

# ---- P3 members: replace / replaceCb ---------------------------------------
# Both scan like matches/split (remainder + empty-match advance-by-one, absolute
# assembly of the output string) and are string-returners: they SET RESULT and
# BODY-ECHO it (owner P0) so `out=$(TRegEx.replace ...)` is ergonomic. Default
# is replace-ALL (Delphi/.NET); maxCount (arg 4; 0/''/'-' = all) caps the number
# of REPLACEMENTS. rc 0 / 2 invalid (invalid -> the original text unchanged).

# Internal: expand a replacement TEMPLATE against the current match. Reads the
# in-scope __tre_g ([0]=whole match, 1..=groups) and writes __trx_expanded.
# Grammar (Delphi/.NET $-form): $$ -> literal $ ; $& or $0 -> whole match ;
# $1..$9 -> group (single digit) ; ${n} -> group n (any width) ; an out-of-range
# or non-group $x is kept LITERAL. Sed metacharacters & and \ are LITERAL (a
# documented delta vs sed) — only $ is special. Pure bash, fork-free.
TRegEx._expandRepl() {
    local __t="$1" __o="" __i=0 __len=${#1} __c __d __ng=$(( ${#__tre_g[@]} - 1 ))
    while (( __i < __len )); do
        __c="${__t:__i:1}"
        if [[ "$__c" != '$' ]]; then __o+="$__c"; (( __i++ )); continue; fi
        __d="${__t:__i+1:1}"
        case "$__d" in
            '$') __o+='$'; (( __i += 2 )) ;;
            '&') __o+="${__tre_g[0]}"; (( __i += 2 )) ;;
            [0-9])
                if [[ "$__d" == 0 ]]; then __o+="${__tre_g[0]}"
                elif (( __d <= __ng )); then __o+="${__tre_g[__d]}"
                else __o+="\$$__d"; fi
                (( __i += 2 )) ;;
            '{')
                local __j=$(( __i + 2 )) __num=""
                while (( __j < __len )) && [[ "${__t:__j:1}" == [0-9] ]]; do
                    __num+="${__t:__j:1}"; (( __j++ ))
                done
                if [[ -n "$__num" && "${__t:__j:1}" == '}' ]]; then
                    if (( 10#$__num == 0 )); then __o+="${__tre_g[0]}"
                    elif (( 10#$__num <= __ng )); then __o+="${__tre_g[10#$__num]}"
                    else __o+="\${$__num}"; fi
                    __i=$(( __j + 1 ))
                else
                    __o+='$'; (( __i++ ))
                fi ;;
            *) __o+='$'; (( __i++ )) ;;
        esac
    done
    __trx_expanded="$__o"
}

# Shared scan engine for replace/replaceCb. $1 text $2 pattern $3 mode
# (repl|cb) $4 template-or-cbname $5 maxCount|- $6 flags. Builds the output in
# __trx_out; on invalid pattern leaves the text unchanged. Sets RESULT + echoes.
TRegEx._replaceScan() {
    local __trx_text="$1" __trx_re="$2" __trx_mode="$3" __trx_arg="$4"
    local __trx_limit="${5:-0}" __trx_flags="${6:-}"
    [[ "$__trx_limit" == "-" || -z "$__trx_limit" ]] && __trx_limit=0
    local __trx_rem="$1" __trx_out="" __trx_done=0 __trx_expanded
    local __tre_rc __tre_m; local -a __tre_g
    while : ; do
        TRegEx._match1 "$__trx_rem" "$__trx_re" "$__trx_flags"
        if (( __tre_rc == 2 )); then
            TRegEx._invalid "$__trx_mode" "$__trx_re"; RESULT="$__trx_text"; printf '%s\n' "$__trx_text"; return 2
        fi
        (( __tre_rc != 0 )) && break
        (( __trx_limit > 0 && __trx_done >= __trx_limit )) && break
        local __trx_m="$__tre_m" __trx_pre="${__trx_rem%%"$__tre_m"*}" __trx_loff
        __trx_loff=${#__trx_pre}
        __trx_out+="${__trx_rem:0:__trx_loff}"
        if [[ "$__trx_mode" == cb ]]; then
            REPLY=""
            "$__trx_arg" "${__tre_g[0]}" "${__tre_g[@]:1}"
            __trx_out+="$REPLY"
        else
            TRegEx._expandRepl "$__trx_arg"
            __trx_out+="$__trx_expanded"
        fi
        (( __trx_done++ ))
        local __trx_adv
        if [[ -z "$__trx_m" ]]; then
            (( __trx_loff < ${#__trx_rem} )) && __trx_out+="${__trx_rem:__trx_loff:1}"
            __trx_adv=$(( __trx_loff + 1 ))
        else
            __trx_adv=$(( __trx_loff + ${#__trx_m} ))
        fi
        if (( __trx_adv > ${#__trx_rem} )); then __trx_rem=""; break; fi
        __trx_rem="${__trx_rem:__trx_adv}"
    done
    __trx_out+="$__trx_rem"
    RESULT="$__trx_out"
    printf '%s\n' "$__trx_out"
    return 0
}

# replace text pattern replacement [maxCount|-] [flags]  ->  RESULT + echo
TRegEx.replace() {
    TRegEx._replaceScan "$1" "$2" repl "$3" "${4:-0}" "${5:-}"
}

# replaceCb text pattern cbName [maxCount|-] [flags]  ->  RESULT + echo
#   The callback is invoked as:  cbName "<wholeMatch>" "<group1>" "<group2>" ...
#   and must set REPLY to the replacement text (fork-free; do NOT echo). Example:
#     wrap() { REPLY="<$1>"; }   # $1 = whole match
#     TRegEx.replaceCb "$s" "$re" wrap
TRegEx.replaceCb() {
    TRegEx._replaceScan "$1" "$2" cb "$3" "${4:-0}" "${5:-}"
}

# Finalize the class.
build TRegEx
