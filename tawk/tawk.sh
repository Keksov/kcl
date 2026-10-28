#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%tawk.sh}../../kbool.sh" || return
kk.unit tawk || return $__kk_unit_rc

# Locale self-heal (kcl/README.md §1.6). A path, a program and the bytes gawk
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
#   * the local prefix `__taw_` — bash scopes locals DYNAMICALLY, so a caller
#     array named `__taw_v` would bind the scratch nameref a member body holds;
#   * the suffixes `_progs`, `_vnames`, `_vvals` — this unit's own storage:
#     `a.toArray a_progs` would turn the records into the NEXT run's program,
#     `a_vnames`/`a_vvals` into its variables.
# Each append is idempotent (only if absent), and the scratch globals are
# released right after, so the unit leaves `__TAW_SEQ` and the two inplace
# caches `__TAW_IPC` / `__TAW_APC` (below) behind.
declare -g __taw_seen=0
declare -g __taw_p=''
declare -g __taw_s=''
for __taw_p in "${TUTIL_OUT_PREFIXES[@]}"; do
    if [[ "$__taw_p" == "__taw_" ]]; then
        __taw_seen=1
    fi
done
if [[ "$__taw_seen" != "1" ]]; then
    TUTIL_OUT_PREFIXES+=( __taw_ )
fi
for __taw_s in _progs _vnames _vvals; do
    __taw_seen=0
    for __taw_p in "${TUTIL_OUT_SUFFIXES[@]}"; do
        if [[ "$__taw_p" == "$__taw_s" ]]; then
            __taw_seen=1
        fi
    done
    if [[ "$__taw_seen" != "1" ]]; then
        TUTIL_OUT_SUFFIXES+=( "$__taw_s" )
    fi
done
unset -v __taw_seen __taw_p __taw_s

# Monotonic sequence for `TAwk.apply`'s throw-away instance name (PLAN §2.7): a
# FIXED name is deleted out from under an outer `apply` by a nested one, so the
# name is `__taw_a_${BASHPID}_${__TAW_SEQ}`. Same idiom as TSed's `__TSD_SEQ`.
declare -g __TAW_SEQ=0

# The inplace lookup caches (L3.5-9, design L3_4 I3): per resolved gawk path,
# `__TAW_IPC[$cmd]` = the absolute path of gawk's own inplace.awk ('' = none was
# found) and `__TAW_APC[$cmd]` = the raw default AWKPATH that gawk printed (the
# I4 line quotes it). Declared once per process, so `kk.unit --forget tawk` +
# re-source keeps them. The test is the unit header's: `${A[@]@a}` is set -u safe
# (an unset array is just empty), fork-free, and says `A` for a filled associative
# array; an EMPTY one reads as empty and is re-declared, which loses nothing.
# Filled by `tawk._inplace`, keyed by the `cmd` string (a relative `cmd` keeps its
# answer across PATH / cwd changes).
[[ ${__TAW_IPC[@]@a} == *A* ]] || declare -gA __TAW_IPC=()
[[ ${__TAW_APC[@]@a} == *A* ]] || declare -gA __TAW_APC=()

# ---------------------------------------------------------------------------
# TAwk — the GNU Awk wrapper over TUtil (gawk 5.0.0 under bash 5.2.37 via Git
# for Windows, 5.4.0 under bash 5.3.9 via msys64; D4: the GNU dialect).
#
#     source kcl/tawk/tawk.sh
#
#     TAwk.apply '{print $2}' data.txt       # the one-liner, streamed, sandboxed
#
#     TAwk.new a '{print $1}' in.txt         # or an instance, for options
#     a.fieldSep = :                         # -F :
#     a.setVar limit 'a\b'                   # VERBATIM (owner Q2)
#     a.addProgram 'END{print NR}'           # more chunks, in order
#     a.toArray lines                        # RESULT = ${#lines[@]}
#     a.sandbox = 0; a.inPlace = 1           # in-place: `run` only
#     a.run
#     a.delete
#
# ---- The pinned argv (PLAN §1.2) ------------------------------------------
#   gawk [--sandbox] [-F FS] [-v RS=\0 -v ORS=\0] [-v BINMODE=3 | the CR RS]
#        [-i ABSOLUTE/inplace.awk [-v inplace::suffix=enc(SFX)]]
#        [EXTRA OPTIONS] [-v NAME=enc(VALUE) ...] [-e program] [-e chunk ...]
#        [-f FILE] [-- PATH...]
#
#  * gawk concatenates `-e` and `-f` sources IN ARGUMENT ORDER, each `-e` a
#    complete source of its own. An EMPTY chunk is never emitted: gawk drops
#    `-e ''` with a warning, and with no other program the first path would
#    become THE program (critic blocker 1);
#  * the setVar words come AFTER the extras, so they win over an
#    `addArg -v NAME=…` of the same name; in insertion order;
#  * `-v BINMODE=3` is emitted when `binary`, `inPlace` OR `nullData` is 1: in
#    text mode gawk strips the CR on input, so `-i inplace` would rewrite CRLF
#    to LF on disk and a NUL record would lose an embedded CR. The derivation
#    lives here only; the `binary` property is never written;
#  * without that BINMODE the build is TEXT mode: the line-end CR of a CRLF
#    input never reaches the PROGRAM, on any platform — cygwin/msys gawk drops
#    it itself; elsewhere the build emits the CR-optional RS in the BINMODE
#    slot, before the extras and the setVar words, so a user's RS wins. No
#    output strip (a CR the program writes is kept), except the `--posix` /
#    `--traditional` fallback (tutil README §3, owner DL11);
#  * the inplace extension is included by its ABSOLUTE path: `-i inplace` is
#    resolved through AWKPATH, which starts with `.`, so a planted
#    `./inplace.awk` would load instead — with the sandbox off (critic major 6).
#    The path is gawk's OWN inplace.awk, found through the default AWKPATH of
#    the gawk that will run (`tawk._inplace`: the first ABSOLUTE entry holding a
#    readable inplace.awk; cached per gawk path, one fork the first time) —
#    `/usr/share/awk` on Linux, `/usr/local/share/awk` on FreeBSD. None found =
#    rc 2 with one line naming the AWKPATH (L3.5-9);
#  * `inplace::suffix`, not `INPLACE_SUFFIX` (5.4 only), its value encoded like setVar's;
#  * `--sandbox` is emitted unless `sandbox` is EXACTLY `0` — it fails closed
#    (owner Q1).
#
# ---- rc 2 at buildArgv: nothing runs, one kk.debug line (PLAN §2.2) --------
#   * `cmd` empty (no GNU awk found: the line carries ktool's reason, e.g. the
#     package to install); NO program (`program` '', every chunk '', `programFile`
#     ''); `programFile` = `-` (gawk would read the program from stdin);
#   * a path operand that gawk reads as an ASSIGNMENT
#     (`^([A-Za-z_][A-Za-z0-9_]*::)?[A-Za-z_][A-Za-z0-9_]*=`) — the caller
#     passes `./NAME=…`;
#   * `inPlace = 1` with no path or with `-`, or with `sandbox` ≠ `0` (the
#     sandbox refuses the extension), or when gawk's inplace.awk is not in its
#     default AWKPATH (that lookup runs last among the inPlace checks; a later
#     refusal may already have paid the one cached probe fork);
#     `backupSuffix` set with `inPlace = 0`;
#   * a stored variable name that is not an awk identifier or is a keyword,
#     builtin or gawk array (setVar refuses those already; `_vnames` is a
#     global anyone can write, so the build checks again);
#   * the extras (`tawk._scanExtras`): the deny-list, `--`, a non-option word (it
#     would become THE program), an argument-taking option left dangling at the
#     end (it would swallow the first generated word).
#
# ---- mapRc (owner Q3) ------------------------------------------------------
#   0 -> 0;  1, 2 -> 1 + one kk.debug line ("gawk exited N (a gawk error, or
#   the program's exit N)");  127 -> the base wording;  anything else — a
#   program's `exit N` — -> 1 SILENT, the raw value in `lastRc`.
#
# ---- Traps this unit is written around ------------------------------------
#  * The constructor calls `parent.constructor gawk` EXPLICITLY (`inherited`
#    in a constructor forwards "$@" and would make PROGRAM the command), then
#    `tutil._gnu awk` (cmd = the GNU awk ktool resolved, or '' with the reason).
#  * EVERY declared var is assigned in `Create`; `sandbox` to 1.
#  * No `var` is named like a TUtil or kklass member.
#  * Booleans are compared as strings (`[[ "$x" == 1 ]]`) — except `sandbox`,
#    which fails closed (`[[ "$sandbox" != "0" ]]`).
#  * A `func` answering a value and a non-zero rc ends `kk._return V; return N`.
#  * `${inst}_argv` is rebuilt through a nameref.
#  * The encoder (`tawk._enc`) is a plain function, never a member body, and
#    its quoted-pattern spelling is literal on bash 5.2 and 5.3.
#  * A CALLBACK that assigns a bare `program=`, `programFile=`, `sandbox=0` or
#    `inPlace=` writes the INSTANCE's property (dynamic scoping) — callbacks
#    declare `local`.
# ---------------------------------------------------------------------------
class TAwk : TUtil
    public
        var program         # the FIRST program chunk (-e); '' = none
        var programFile     # -f FILE ('' = off), after the -e chunks; `-` refused
        var fieldSep        # -F FS ('' = off; awk semantics: regex, escapes processed)
        var nullData        # -v RS='\0' -v ORS='\0' -> derives the sinks' -0 AND BINMODE=3
        var binary          # -v BINMODE=3 (keep the CR; also derived)
        var sandbox         # --sandbox, DEFAULT 1 (owner Q1); off ONLY for exactly '0'
        var inPlace         # -i <gawk's inplace.awk> (needs sandbox = 0; sinks refuse)
        var backupSuffix    # -v inplace::suffix=enc(SFX) (only with inPlace = 1)
        var _nulDerived     # private bookkeeping for the nullData -> -0 derivation
        constructor Create  # [PROGRAM [PATH...]]
        destructor  Destroy # frees ${inst}_paths, _progs, _vnames, _vvals, then inherited
        proc paths          # PATH... — REPLACES the operand list
        proc addProgram     # CHUNK... — appended after `program`; '' is never emitted
        proc clearPrograms  # empties the list (not `program`)
        proc setVar         # NAME VALUE — VERBATIM; a repeated NAME replaces in place
        proc clearVars
        override func buildArgv
        override func mapRc
        override proc each
        override func toArray
        override func toList
        override func first
        override func count
        static proc apply   # PROGRAM PATH... — `gawk --sandbox -e PROGRAM -- PATH...`
end

# ===========================================================================
# Internal helpers (plain functions, never class members)
# ===========================================================================

# tawk._isId WORD — rc 0 when WORD is an awk identifier `[A-Za-z_][A-Za-z0-9_]*`.
# The letters are spelled out: a bracket RANGE may match a non-ASCII letter in
# a UTF-8 locale, and gawk treats `é=v` as a file, not an assignment.
tawk._isId() {
    case "${1-}" in
        ''|[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_]*)
            return 1
            ;;
        *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]*)
            return 1
            ;;
    esac
    return 0
}

# tawk._isAssign PATH — rc 0 when gawk would read the operand PATH as an
# assignment `[NS::]NAME=VALUE` instead of a file (PLAN §1.1): measured, `k=v`,
# `a::b=v` and `awk::x=v` assign; `1x=v`, `é=v`, `x.y=v`, `C:/x=y`, `C:\x=y`
# are files.
tawk._isAssign() {
    local __taw_w="${1-}" __taw_h=''
    if [[ "$__taw_w" != *=* ]]; then
        return 1
    fi
    __taw_h="${__taw_w%%=*}"
    if [[ "$__taw_h" == *::* ]]; then
        tawk._isId "${__taw_h%%::*}" || return 1
        tawk._isId "${__taw_h#*::}" || return 1
        return 0
    fi
    tawk._isId "$__taw_h"
}

# tawk._badName NAME — rc 0 when NAME must not be a `setVar` name, with the
# reason in the CALLER's `__taw_why`. gawk answers each of these with a fatal
# rc 2 (measured on 5.0 and 5.4): not an identifier, a keyword (incl. `switch`,
# `case`, `default`), a builtin function of gawk 5.4 (incl. `mkbool`), or one
# of its special arrays.
tawk._badName() {
    local __taw_n="${1-}"
    if ! tawk._isId "$__taw_n"; then
        __taw_why="is not an awk identifier ([A-Za-z_][A-Za-z0-9_]*; a namespaced name is not accepted)"
        return 0
    fi
    case "$__taw_n" in
        BEGIN|END|BEGINFILE|ENDFILE|function|func|if|else|while|for|do|break|continue|\
next|nextfile|exit|return|delete|getline|print|printf|in|switch|case|default|\
and|asort|asorti|atan2|bindtextdomain|close|compl|cos|dcgettext|dcngettext|exp|\
fflush|gensub|gsub|index|int|isarray|length|log|lshift|match|mkbool|mktime|or|\
patsplit|rand|rshift|sin|split|sprintf|sqrt|srand|strftime|strtonum|sub|substr|\
system|systime|tolower|toupper|typeof|xor)
            __taw_why="is an awk keyword or gawk builtin (gawk stops with a fatal error)"
            return 0
            ;;
        ENVIRON|PROCINFO|SYMTAB|FUNCTAB)
            __taw_why="is a gawk array (gawk stops with a fatal error)"
            return 0
            ;;
    esac
    return 1
}

# tawk._enc VALUE — the `-v` encoding of PLAN §2.3 into the CALLER's
# `__taw_e`: every backslash doubled, every newline written `\n`, a LEADING
# `@` written `\100` (else `@/…/` is a typed regexp). gawk's escape processing
# of `-v` then gives back exactly VALUE — measured byte-exact on 5.0 and 5.4
# over the §1.1 matrix. The pattern and the replacement are QUOTED, so they are
# literal on bash 5.2 (patsub_replacement) and 5.3 alike.
tawk._enc() {
    local __taw_v="${1-}" __taw_b='\' __taw_nl=$'\n'
    __taw_v="${__taw_v//"$__taw_b"/"$__taw_b$__taw_b"}"
    __taw_v="${__taw_v//"$__taw_nl"/"${__taw_b}n"}"
    if [[ "${__taw_v:0:1}" == "@" ]]; then
        __taw_v="${__taw_b}100${__taw_v:1}"
    fi
    __taw_e="$__taw_v"
    return 0
}

# tawk._longDenied NAME BIN — rc 0 when the long option NAME (the part after
# `--`, or the argument of `-W`, before any `=`) is refused, with the option in
# the CALLER's `__taw_dopt` and the reason in `__taw_why`. getopt matches a long
# option by ANY unambiguous prefix and the two gawk versions disagree on what
# is ambiguous (`--t` is `--traditional` on 5.0, ambiguous on 5.4), so a NAME
# that is a prefix of a denied option is refused, never decided per version
# (PLAN §2.2). The order puts `source` before `sandbox`, `file` before
# `field-separator`, `pretty-print` before `profile`, `dump-variables` before
# `debug`, so the line names the first denied candidate. BIN = 1 (binary mode
# derived) adds `posix` and `traditional`, which silently disable BINMODE.
tawk._longDenied() {
    local __taw_n="${1-}" __taw_bin="${2-0}" __taw_l=''
    local -a __taw_t=(
        "source:is the program — use the property 'program' / addProgram"
        "file:is the program file — use the property 'programFile'"
        "include:loads a source file through AWKPATH — for in-place editing use the property 'inPlace'"
        "load:loads a binary extension"
        "exec:ends gawk's options and takes the program from a file"
        "field-separator:is the field separator — use the property 'fieldSep'"
        "sandbox:is modelled — use the property 'sandbox'"
        "pretty-print:writes a file and does not run the program"
        "gen-pot:does not run the program"
        "help:prints to stdout and does not run the program"
        "usage:prints to stdout and does not run the program"
        "version:prints to stdout and does not run the program"
        "copyright:prints to stdout and does not run the program"
        "dump-variables:writes a file, even under the sandbox"
        "profile:writes a file, even under the sandbox"
        "debug:reads debugger commands from stdin"
        "bignum:loses the input under the gawk 5.4 sandbox"
    )
    if [[ "$__taw_bin" == 1 ]]; then
        __taw_t+=(
            "posix:silently disables BINMODE, which binary / nullData / inPlace needs"
            "traditional:silently disables BINMODE, which binary / nullData / inPlace needs"
        )
    fi
    for __taw_l in "${__taw_t[@]}"; do
        if [[ "${__taw_l%%:*}" == "$__taw_n"* ]]; then
            __taw_dopt="--${__taw_l%%:*}"
            __taw_why="${__taw_l#*:}"
            return 0
        fi
    done
    return 1
}

# tawk._shortLong LETTER BIN — the long name of a denied short option into the
# CALLER's `__taw_ln`; rc 1 when LETTER is not denied.
tawk._shortLong() {
    case "${1-}" in
        e) __taw_ln=source ;;
        f) __taw_ln=file ;;
        i) __taw_ln=include ;;
        l) __taw_ln=load ;;
        E) __taw_ln=exec ;;
        F) __taw_ln=field-separator ;;
        S) __taw_ln=sandbox ;;
        o) __taw_ln=pretty-print ;;
        g) __taw_ln=gen-pot ;;
        h) __taw_ln=help ;;
        V) __taw_ln=version ;;
        C) __taw_ln=copyright ;;
        d) __taw_ln=dump-variables ;;
        p) __taw_ln=profile ;;
        D) __taw_ln=debug ;;
        M) __taw_ln=bignum ;;
        P) if [[ "${2-0}" == 1 ]]; then __taw_ln=posix; else return 1; fi ;;
        c) if [[ "${2-0}" == 1 ]]; then __taw_ln=traditional; else return 1; fi ;;
        *) return 1 ;;
    esac
    return 0
}

# tawk._scanExtras BIN WORD... — the §2.2 scan of the extras, following gawk's
# own getopt. rc 0 = every word passes; rc 1 = refused, with the complete
# refusal line in the CALLER's `__taw_msg`.
#
#   * `--` ends gawk's options (every chunk after it would become an operand);
#   * a word that is not an option (incl. '' and a bare `-`) becomes THE
#     program — gawk stops parsing at the first non-option;
#   * `--NAME[=V]`: NAME goes through `tawk._longDenied`; a NAME that is a
#     prefix of `assign` without `=` takes the NEXT word as its argument;
#   * `-XYZ` is a bundle: each letter is an option until one that takes an
#     argument — `v` and `W` take the rest of the word, or the NEXT word when
#     the rest is empty; `L` takes an optional attached argument; `W`'s
#     argument is a long option and goes through the same table (and, when it
#     is `assign` without `=`, takes one more word);
#   * an argument-taking option with no word left is DANGLING: it would swallow
#     the first word the wrapper generates after the extras.
# A word consumed as an argument is never scanned as an option.
tawk._scanExtras() {
    local __taw_bin="$1"; shift
    local -a __taw_w=( "$@" )
    local __taw_k=0 __taw_n=${#__taw_w[@]} __taw_x='' __taw_nm='' __taw_j=0 __taw_c=''
    local __taw_r='' __taw_ln='' __taw_dopt='' __taw_why='' __taw_need=0
    while (( __taw_k < __taw_n )); do
        __taw_x="${__taw_w[$__taw_k]}"
        __taw_need=0
        case "$__taw_x" in
            --)
                __taw_msg="the extra '--' ends gawk's options, so every program chunk after it would become an operand; the wrapper emits its own '--' before the paths"
                return 1
                ;;
            --*)
                __taw_nm="${__taw_x#--}"
                if tawk._longDenied "${__taw_nm%%=*}" "$__taw_bin"; then
                    __taw_msg="the extra '$__taw_x' is gawk's $__taw_dopt (a long option matches by any prefix), which $__taw_why"
                    return 1
                fi
                if [[ "$__taw_nm" != *=* && -n "$__taw_nm" && "assign" == "$__taw_nm"* ]]; then
                    __taw_need=1
                fi
                ;;
            -?*)
                for (( __taw_j = 1; __taw_j < ${#__taw_x}; __taw_j++ )); do
                    __taw_c="${__taw_x:__taw_j:1}"
                    if tawk._shortLong "$__taw_c" "$__taw_bin"; then
                        tawk._longDenied "$__taw_ln" "$__taw_bin"
                        __taw_msg="the extra '$__taw_x' is gawk's $__taw_dopt (-$__taw_c), which $__taw_why"
                        return 1
                    fi
                    case "$__taw_c" in
                        v)
                            if [[ -z "${__taw_x:__taw_j+1}" ]]; then
                                __taw_need=1
                            fi
                            break
                            ;;
                        W)
                            __taw_r="${__taw_x:__taw_j+1}"
                            if [[ -z "$__taw_r" ]]; then
                                if (( __taw_k + 1 >= __taw_n )); then
                                    __taw_msg="the extra '$__taw_x' is the last one and takes an argument (-W LONG-OPTION): it would swallow the first word the wrapper generates"
                                    return 1
                                fi
                                __taw_k=$(( __taw_k + 1 ))
                                __taw_r="${__taw_w[$__taw_k]}"
                            fi
                            if tawk._longDenied "${__taw_r%%=*}" "$__taw_bin"; then
                                __taw_msg="the extra '-W $__taw_r' is gawk's $__taw_dopt (every long option has a -W spelling, abbreviable), which $__taw_why"
                                return 1
                            fi
                            if [[ "$__taw_r" != *=* && -n "$__taw_r" && "assign" == "$__taw_r"* ]]; then
                                __taw_need=1
                            fi
                            break
                            ;;
                        L)
                            break
                            ;;
                    esac
                done
                ;;
            *)
                __taw_msg="the extra '$__taw_x' is not an option word: gawk stops parsing options at it and takes it as THE program (everything after it would become an operand)"
                return 1
                ;;
        esac
        if [[ "$__taw_need" == 1 ]]; then
            if (( __taw_k + 1 >= __taw_n )); then
                __taw_msg="the extra '$__taw_x' is the last one and takes an argument (-v / --assign NAME=VALUE): it would swallow the first word the wrapper generates"
                return 1
            fi
            __taw_k=$(( __taw_k + 1 ))
        fi
        __taw_k=$(( __taw_k + 1 ))
    done
    return 0
}

# tawk._sinkRefused SINK — the refusal every overridden sink runs FIRST (PLAN
# §2.5). rc 0 = refused (one kk.debug line already written; the caller answers
# rc 2 and runs nothing); rc 1 = go ahead. It reads the member frame's
# `$inPlace` through dynamic scoping, as `tutil._prep` does.
tawk._sinkRefused() {
    if [[ "$inPlace" == 1 ]]; then
        kk.debug "Error: TAwk.${1:-}: in-place editing writes nothing to stdout; use run"
        return 0
    fi
    return 1
}

# tawk._inplace CMD — gawk's own inplace.awk (L3.5-9, design I1-I6). Fills the
# CALLER's `__taw_ip` (the absolute path of inplace.awk in the first ABSOLUTE
# directory of the default AWKPATH of the gawk CMD, '' = none) and `__taw_apv`
# (that AWKPATH, raw, for the refusal line). The default AWKPATH is asked of the
# gawk itself, with AWKPATH unset: `env -u AWKPATH CMD 'BEGIN { print
# ENVIRON["AWKPATH"] }'` (`.:/usr/share/awk` on Linux and msys, `.:/usr/local/
# share/awk` on FreeBSD). Entries that do not start with `/` (`.`, relative,
# empty) are skipped — the include is absolute so that a planted ./inplace.awk
# is never loaded; a directory named inplace.awk does not count (`-f`). Both
# answers are cached per CMD STRING in `__TAW_IPC` / `__TAW_APC` (a "none found"
# too, but only after a probe that exited 0 with an answer), so the fork happens
# once per gawk path and process; a `$( )`
# caller pays it every time (README: warm it in the main shell). `|| rc=$?`: the
# children of the 006 tests run under `set -eu`. AWKLIBPATH is not touched (I6).
tawk._inplace() {
    local __taw_c="${1-}"
    if [[ -n ${__TAW_IPC[$__taw_c]+x} ]]; then
        __taw_ip="${__TAW_IPC[$__taw_c]}"
        __taw_apv="${__TAW_APC[$__taw_c]}"
        return 0
    fi
    local __taw_raw='' __taw_ent='' __taw_found='' __taw_prc=0
    __taw_raw="$(env -u AWKPATH "$__taw_c" 'BEGIN { print ENVIRON["AWKPATH"] }' </dev/null 2>/dev/null)" || __taw_prc=$?
    __taw_raw="${__taw_raw%%$'\n'*}"        # the first line only
    __taw_raw="${__taw_raw%[[:cntrl:]]}"    # a trailing CR (a text-mode gawk on msys may print one)
    local __taw_rest="$__taw_raw:"
    while [[ -n "$__taw_rest" ]]; do
        __taw_ent="${__taw_rest%%:*}"
        __taw_rest="${__taw_rest#*:}"
        if [[ "$__taw_ent" == /* && -f "$__taw_ent/inplace.awk" && -r "$__taw_ent/inplace.awk" ]]; then
            __taw_found="$__taw_ent/inplace.awk"
            break
        fi
    done
    # Cache only a probe that WORKED (rc 0, an answer): a failed one (a fork
    # failure under a commit limit, a gawk that died) is a miss for this call
    # only, so the next build probes again.
    if (( __taw_prc == 0 )) && [[ -n "$__taw_raw" ]]; then
        __TAW_APC[$__taw_c]="$__taw_raw"
        __TAW_IPC[$__taw_c]="$__taw_found"
    fi
    __taw_ip="$__taw_found"
    __taw_apv="$__taw_raw"
    return 0
}

# ===========================================================================
# Members
# ===========================================================================

# Create [PROGRAM [PATH...]] — PLAN §1.2, §2.1. PROGRAM becomes `program`,
# every further argument a path. `parent.constructor gawk` is spelled out, EVERY
# declared var is assigned (`sandbox` = 1, the owner's Q1 default),
# `tutil._gnu awk` resolves the tool into `cmd` (L3.4: no GNU awk = `cmd` ''
# and `_toolErr`, `.new` still succeeds; the first buildArgv answers rc 2), and
# the four per-instance arrays are real INDEXED globals next to `${inst}_data`
# (the variables keep insertion order), released by the destructor.
TAwk.Create() {
    parent.constructor gawk
    tutil._gnu awk
    program="${1:-}"
    programFile=''
    fieldSep=''
    nullData=0
    binary=0
    sandbox=1
    inPlace=0
    backupSuffix=''
    _nulDerived=0
    declare -ga "${__inst__}_paths=()"
    declare -ga "${__inst__}_progs=()"
    declare -ga "${__inst__}_vnames=()"
    declare -ga "${__inst__}_vvals=()"
    local -n __taw_p="${__inst__}_paths"
    __taw_p=( "${@:2}" )
    return 0
}

# Destroy — release this class's four arrays, then chain to TUtil.Destroy.
TAwk.Destroy() {
    unset -v "${__inst__}_paths" "${__inst__}_progs" "${__inst__}_vnames" "${__inst__}_vvals"
    inherited
    return 0
}

# paths PATH... — REPLACE the operand list. No argument = the stdin form.
TAwk.paths() {
    local -n __taw_p="${__inst__}_paths"
    __taw_p=( "$@" )
    return 0
}

# addProgram CHUNK... — append to the chunk list, emitted after `program` in
# call order. Each chunk is compiled by gawk as a COMPLETE source of its own;
# an EMPTY chunk is stored but never emitted.
TAwk.addProgram() {
    local -n __taw_x="${__inst__}_progs"
    __taw_x+=( "$@" )
    return 0
}

# clearPrograms — empty the list. `program` is a property and is left alone.
TAwk.clearPrograms() {
    local -n __taw_x="${__inst__}_progs"
    __taw_x=()
    return 0
}

# setVar NAME VALUE — owner Q2: VALUE arrives in the program VERBATIM (the
# encoding is buildArgv's). A NAME gawk would reject is rc 2 with one line and
# nothing stored; a repeated NAME replaces its value in its original slot.
TAwk.setVar() {
    if (( $# != 2 )); then
        kk.debug "Error: TAwk.setVar: usage: setVar NAME VALUE (got $# argument(s))"
        return 2
    fi
    local __taw_why=''
    if tawk._badName "$1"; then
        kk.debug "Error: TAwk.setVar: the name '$1' $__taw_why"
        return 2
    fi
    local -n __taw_vn="${__inst__}_vnames"
    local -n __taw_vv="${__inst__}_vvals"
    local __taw_k
    for __taw_k in "${!__taw_vn[@]}"; do
        if [[ "${__taw_vn[$__taw_k]}" == "$1" ]]; then
            __taw_vv[$__taw_k]="$2"
            return 0
        fi
    done
    __taw_vn+=( "$1" )
    __taw_vv[$(( ${#__taw_vn[@]} - 1 ))]="$2"
    return 0
}

# clearVars — forget every setVar pair.
TAwk.clearVars() {
    local -n __taw_vn="${__inst__}_vnames"
    local -n __taw_vv="${__inst__}_vvals"
    __taw_vn=()
    __taw_vv=()
    return 0
}

# buildArgv — the override, and the single truth about what will run. RESULT =
# the number of words, rc 0; on a refusal `kk._return ""`, rc 2, one kk.debug
# line, `${inst}_argv` left EMPTY.
TAwk.buildArgv() {
    local -n __taw_v="${__inst__}_argv"
    local -n __taw_p="${__inst__}_paths"
    local -n __taw_x="${__inst__}_progs"
    local -n __taw_a="${__inst__}_args"
    local -n __taw_vn="${__inst__}_vnames"
    local -n __taw_vv="${__inst__}_vvals"
    __taw_v=()

    # ---- the rc 2 list, checked before a single word is built -------------
    if [[ -z "$cmd" ]]; then
        kk.debug "Error: TAwk.buildArgv: ${_toolErr:-cmd is empty; there is nothing to run}"
        kk._return ""
        return 2
    fi
    local __taw_s='' __taw_has=0
    if [[ -n "$program" || -n "$programFile" ]]; then
        __taw_has=1
    else
        for __taw_s in "${__taw_x[@]}"; do
            if [[ -n "$__taw_s" ]]; then
                __taw_has=1
                break
            fi
        done
    fi
    if [[ "$__taw_has" != 1 ]]; then
        kk.debug "Error: TAwk.buildArgv: no program — program is '', every addProgram chunk is empty and programFile is ''; gawk would take the first path AS the program (and may read stdin)"
        kk._return ""
        return 2
    fi
    if [[ "$programFile" == "-" ]]; then
        kk.debug "Error: TAwk.buildArgv: programFile '-' makes gawk read the program from stdin; give a file"
        kk._return ""
        return 2
    fi
    for __taw_s in "${__taw_p[@]}"; do
        if tawk._isAssign "$__taw_s"; then
            kk.debug "Error: TAwk.buildArgv: the path '$__taw_s' looks like an awk assignment NAME=VALUE — gawk would assign it, not read it; pass it as './$__taw_s'"
            kk._return ""
            return 2
        fi
    done
    if [[ "$inPlace" == 1 ]]; then
        if (( ${#__taw_p[@]} == 0 )); then
            kk.debug "Error: TAwk.buildArgv: inPlace = 1 with no path; in-place editing has no stdin form — give the file(s) to edit"
            kk._return ""
            return 2
        fi
        for __taw_s in "${__taw_p[@]}"; do
            if [[ "$__taw_s" == "-" ]]; then
                kk.debug "Error: TAwk.buildArgv: inPlace = 1 with the path '-'; gawk cannot edit stdin in place"
                kk._return ""
                return 2
            fi
        done
        if [[ "$sandbox" != "0" ]]; then
            kk.debug "Error: TAwk.buildArgv: inPlace = 1 needs sandbox = 0 — gawk's sandbox refuses the inplace extension (sandbox is '$sandbox')"
            kk._return ""
            return 2
        fi
        # gawk's own inplace.awk, by ABSOLUTE path (L3.5-9, I1-I5): after the
        # checks above (a later refusal may already have paid the one cached
        # probe fork); a plain function that
        # fills the two locals (never a `$( )`), before anything is derived.
        local __taw_ip='' __taw_apv=''
        tawk._inplace "$cmd"
        if [[ -z "$__taw_ip" ]]; then
            kk.debug "Error: TAwk.buildArgv: gawk's inplace.awk not found in AWKPATH '$__taw_apv' ($cmd)"
            kk._return ""
            return 2
        fi
    fi
    if [[ -n "$backupSuffix" && "$inPlace" != 1 ]]; then
        kk.debug "Error: TAwk.buildArgv: backupSuffix '$backupSuffix' with inPlace = 0; the suffix only means something to in-place editing — set inPlace = 1 or clear backupSuffix"
        kk._return ""
        return 2
    fi
    local __taw_why='' __taw_k
    for __taw_k in "${!__taw_vn[@]}"; do
        if tawk._badName "${__taw_vn[$__taw_k]}"; then
            kk.debug "Error: TAwk.buildArgv: the variable name '${__taw_vn[$__taw_k]}' in ${__inst__}_vnames $__taw_why"
            kk._return ""
            return 2
        fi
    done
    local __taw_bin=0
    if [[ "$binary" == 1 || "$inPlace" == 1 || "$nullData" == 1 ]]; then
        __taw_bin=1
    fi
    local __taw_msg=''
    if (( ${#__taw_a[@]} > 0 )) && ! tawk._scanExtras "$__taw_bin" "${__taw_a[@]}"; then
        kk.debug "Error: TAwk.buildArgv: $__taw_msg"
        kk._return ""
        return 2
    fi

    # ---- the CR contract (tutil README §3, owner DL11) ---------------------
    # Text mode = no BINMODE (binary, inPlace and nullData all off).
    # cygwin/msys gawk drops the line-end CR on input itself; elsewhere
    # (`tutil._keepsCr`) the build emits `-v RS='\r?\n'` BEFORE the extras and
    # the setVar words, so the PROGRAM never sees that CR either (`$NF`,
    # `length`, `NF` on a blank CRLF line) — and a user's RS (setVar, an extra
    # `-v RS=`, `BEGIN{RS=…}`, `RS=""`) still wins, being later. Nothing goes to
    # TUtil's output strip: a CR the program writes on purpose (`ORS="\r\n"`,
    # `printf "x\r\n"`) is kept on every platform.
    #
    # The one exception: `--posix` / `--traditional` (`-P` / `-c`, any prefix,
    # `-W posix`) among the extras make gawk use only RS's FIRST character —
    # the CR — which would wreck every record. Then no RS is emitted and the
    # build falls back to TUtil's output strip (`_textMode = 1`, one
    # `kk.debug` line): the records lose the CR, the program still sees it.
    # The scan is `tawk._scanExtras` with BIN = 1, whose only extra refusals
    # are exactly those two options (the BIN = 0 scan above already passed).
    # `_textMode` is derived the same way on every platform.
    _textMode=0
    local __taw_rs=0
    if [[ "$__taw_bin" != 1 ]]; then
        local __taw_px=0
        if (( ${#__taw_a[@]} > 0 )); then
            local __taw_msg2="$__taw_msg"
            if ! tawk._scanExtras 1 "${__taw_a[@]}"; then
                __taw_px=1
            fi
            __taw_msg="$__taw_msg2"
        fi
        if [[ "$__taw_px" == 1 ]]; then
            _textMode=1
            if tutil._keepsCr; then
                kk.debug "Warning: TAwk.buildArgv: --posix/--traditional among the extras: gawk would split records on the CR alone, so no RS is set — the records lose the line-end CR, but the program sees it"
            fi
        elif tutil._keepsCr; then
            __taw_rs=1
        fi
    fi

    # ---- the nullData -> -0 derivation (PLAN §2.4, tgrep's P3-F1 guard) ----
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

    # ---- the argv, in the pinned order -------------------------------------
    __taw_v=( "$cmd" )
    # `sandbox` FAILS CLOSED (owner Q1): dropped ONLY for the exact string `0`.
    if [[ "$sandbox" != "0" ]]; then __taw_v+=( --sandbox ); fi
    if [[ -n "$fieldSep" ]]; then __taw_v+=( -F "$fieldSep" ); fi
    if [[ "$nullData" == 1 ]]; then __taw_v+=( -v 'RS=\0' -v 'ORS=\0' ); fi
    # The derived BINMODE. Nothing is written back to `binary`. Without it the
    # build is TEXT mode, and on a platform whose gawk keeps the CR the RS of
    # the CR contract (above) takes this slot — before the extras and setVar.
    if [[ "$binary" == 1 || "$inPlace" == 1 || "$nullData" == 1 ]]; then
        __taw_v+=( -v BINMODE=3 )
    fi
    if [[ "$__taw_rs" == 1 ]]; then
        __taw_v+=( -v 'RS=\r?\n' )
    fi
    # `-v` escape-processes its value, so the suffix goes through the same
    # enc() as setVar (reviewer ruling on P0, question 6): `.b\k` names the
    # backup `FILE.b\k`, not `FILE.bk` with a warning. No `$( )`: the helper
    # writes `__taw_e` in this frame.
    local __taw_e=''
    if [[ "$inPlace" == 1 ]]; then
        __taw_v+=( -i "$__taw_ip" )
        if [[ -n "$backupSuffix" ]]; then
            tawk._enc "$backupSuffix"
            __taw_v+=( -v "inplace::suffix=$__taw_e" )
        fi
    fi
    if (( ${#__taw_a[@]} > 0 )); then __taw_v+=( "${__taw_a[@]}" ); fi
    for __taw_k in "${!__taw_vn[@]}"; do
        tawk._enc "${__taw_vv[$__taw_k]-}"
        __taw_v+=( -v "${__taw_vn[$__taw_k]}=$__taw_e" )
    done
    if [[ -n "$program" ]]; then __taw_v+=( -e "$program" ); fi
    for __taw_s in "${__taw_x[@]}"; do
        if [[ -n "$__taw_s" ]]; then __taw_v+=( -e "$__taw_s" ); fi
    done
    if [[ -n "$programFile" ]]; then __taw_v+=( -f "$programFile" ); fi
    if (( ${#__taw_p[@]} > 0 )); then __taw_v+=( -- "${__taw_p[@]}" ); fi

    kk._return "${#__taw_v[@]}"
    return 0
}

# mapRc RAW — owner Q3. gawk's own statuses are 1 (a syntax error or a fatal
# runtime error) and 2 (a FATAL missing input or `-f` file, a sandbox refusal,
# an illegal `-v`). A program's `exit N` leaves with N mod 256, so `exit 1` and
# `exit 2` are indistinguishable from those — the line says so. Any other
# non-zero status can only be the program's and is NOT an error: rc 1, silent,
# the raw value in `lastRc`.
TAwk.mapRc() {
    local __taw_raw="${1:-}"
    case "$__taw_raw" in
        0)
            kk._return "0"
            return 0
            ;;
        127)
            kk.debug "Error: TAwk.mapRc: command not found (raw rc 127)"
            ;;
        1|2)
            kk.debug "Error: TAwk.mapRc: gawk exited $__taw_raw (a gawk error, or the program's exit $__taw_raw)"
            ;;
    esac
    kk._return "1"
    return 0
}

# ---------------------------------------------------------------------------
# The five sinks (PLAN §2.5). Each runs `tawk._sinkRefused` FIRST, then the base
# sink through the rc-PRESERVING spelling: `build` compiles a
# `kk._return "$RESULT"` trailer onto a `func`, so a body that merely ENDS on
# `inherited X "$@"` would answer rc 0 where the base answered 1. The funcs
# capture the rc, save RESULT at once and re-raise both; the proc `each` has no
# return channel and re-raises the rc alone.
# ---------------------------------------------------------------------------

TAwk.each() {
    if tawk._sinkRefused each; then
        return 2
    fi
    local __taw_rc=0
    inherited each "$@" || __taw_rc=$?
    return "$__taw_rc"
}

TAwk.toArray() {
    if tawk._sinkRefused toArray; then
        kk._return ""
        return 2
    fi
    local __taw_rc=0
    inherited toArray "$@" || __taw_rc=$?
    local __taw_n="$RESULT"
    kk._return "$__taw_n"
    return "$__taw_rc"
}

TAwk.toList() {
    if tawk._sinkRefused toList; then
        kk._return ""
        return 2
    fi
    local __taw_rc=0
    inherited toList "$@" || __taw_rc=$?
    local __taw_n="$RESULT"
    kk._return "$__taw_n"
    return "$__taw_rc"
}

TAwk.first() {
    if tawk._sinkRefused first; then
        kk._return ""
        return 2
    fi
    local __taw_rc=0
    inherited first "$@" || __taw_rc=$?
    local __taw_n="$RESULT"
    kk._return "$__taw_n"
    return "$__taw_rc"
}

TAwk.count() {
    if tawk._sinkRefused count; then
        kk._return ""
        return 2
    fi
    local __taw_rc=0
    inherited count "$@" || __taw_rc=$?
    local __taw_n="$RESULT"
    kk._return "$__taw_n"
    return "$__taw_rc"
}

# apply PROGRAM PATH... — the one-liner (PLAN §2.7): `gawk --sandbox -e PROGRAM
# -- PATH...` as a STREAM, with the rc mapped. A `static proc`: it prints
# gawk's stdout and never calls `kk._return`.
#
# An EMPTY PROGRAM is rc 2: gawk drops `-e ''` and would compile the first path
# as the program (critic blocker 1). At least ONE path is required: with none
# gawk would read the caller's stdin. The sandbox is forced on. An
# assignment-looking path is refused by buildArgv (rc 2).
TAwk.apply() {
    if (( $# < 2 )); then
        kk.debug "Error: TAwk.apply: usage: TAwk.apply PROGRAM PATH... — at least one path is required (with none gawk would read the caller's stdin); build an instance for the stdin form"
        return 2
    fi
    if [[ -z "$1" ]]; then
        kk.debug "Error: TAwk.apply: an empty PROGRAM — gawk drops -e '' and would compile the first path as the program"
        return 2
    fi
    __TAW_SEQ=$(( __TAW_SEQ + 1 ))
    local __taw_i="__taw_a_${BASHPID}_${__TAW_SEQ}"
    TAwk.new "$__taw_i" "$1" "${@:2}"
    "$__taw_i".sandbox = 1
    local __taw_rc=0
    "$__taw_i".run || __taw_rc=$?
    "$__taw_i".delete
    return "$__taw_rc"
}

# Finalize: extract the bodies above into the `TAwk` class and generate the
# per-instance wrappers.
build TAwk
