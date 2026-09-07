#!/bin/bash

# kcl/tcustomapplication — Free Pascal's CustApp.TCustomApplication, ported.
#
# Upstream reference: FPC 3.2.2 `packages/fcl-base/src/custapp.pp`
# (https://gitlab.com/freepascal.org/fpc/source/-/raw/release_3_2_2/packages/fcl-base/src/custapp.pp).
# The option parser is a line-by-line port of that file's `FindOptionIndex`,
# `GetOptionAtIndex`, `GetOptionValue(s)`, `HasOption`, `CheckOptions` and
# `GetNonOptions` (decision D4, kcl review 2026-09-06 — phase P4). Argument
# indices are FPC's: `Params[0]` is the executable name, `Params[1]` the first
# argument, `ParamCount` the number of arguments, and every position in an
# error message is that 1-based index.
#
# See README.md for the API table and the list of deliberate differences.

# Re-source guard (kcl review 2026-09-06, X-SETU / decision D7): every unit is
# sourceable — and re-sourceable — from a script running `set -eu`, and building
# the class a second time is pure waste.
if [[ -n "${_TCUSTOMAPPLICATION_SOURCED:-}" ]]; then
    return
fi
declare -g _TCUSTOMAPPLICATION_SOURCED=1

# Source kklass system (don't override SCRIPT_DIR)
TCUSTOMAPPLICATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TCUSTOMAPPLICATION_DIR/../../kklass/kklass_pascal.sh"
source "$TCUSTOMAPPLICATION_DIR/../../kkore/kuse.sh"

# Character semantics are part of this unit's contract (kcl/README.md 1.6,
# decision D6): CaseSensitiveOptions folds case with ${s,,}/${s^^}, and an empty
# environment means the C locale, where that corrupts UTF-8 on bash 5.2.
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# ============================================================================
# Internal scratch, module-private. The helpers below are plain functions, not
# class members: they cost no kklass dispatch, cannot print into a caller's
# $( ), and hand their answer back through these three globals rather than
# through RESULT (which belongs to the public member that called them).
# ============================================================================
declare -g __TCA_IDX=-1     # tca._findIndex: matching argument index, -1 = none
declare -g __TCA_LONG=0     # tca._findIndex: 1 when that match was a long option
declare -g __TCA_VAL=""     # tca._optionAt:  the extracted option value
declare -g __TCA_ERR=""     # tca._checkOptions: the joined error message

# ----------------------------------------------------------------------------
# tca._isName NAME — rc 0 when NAME may be written to as a caller output array
# (kcl/README.md 1.7). Rejects the framework's reserved names and this unit's
# own `__tca_`/`__TCA_` space, because bash scopes locals dynamically and an
# output name colliding with one of our locals would silently write the local.
# ----------------------------------------------------------------------------
tca._isName() {
    case "${1:-}" in
        ""|*[!A-Za-z0-9_]*|[0-9]*)          return 1 ;;
        this|__inst__|__class__|RESULT|REPLY|IFS|state) return 1 ;;
        __kk_*|__KK_*|__tca_*|__TCA_*)      return 1 ;;
    esac
    return 0
}

# tca._outName NAME INSTANCE — as above, plus the instance's own storage.
tca._outName() {
    tca._isName "${1:-}" || return 1
    case "$1" in
        "${2:-}_data"|"${2:-}_class"|"${2:-}_items") return 1 ;;
    esac
    return 0
}

# ----------------------------------------------------------------------------
# tca._findIndex DATA NAME START_AT — FPC `FindOptionIndex(S, var LongOpt,
# StartAt)`, verbatim: the scan runs DOWNWARD from StartAt (ParamCount when
# StartAt is -1) to index 1, so the LAST occurrence of an option wins (default
# R10). Index 0 is the executable name and is never examined.
#   -> __TCA_IDX  = index, or -1
#   -> __TCA_LONG = 1 when the matching argument was `--name` / `--name=value`
# ----------------------------------------------------------------------------
tca._findIndex() {
    local -n __tca_st="$1"
    local __tca_name="$2" __tca_i="$3"
    local __tca_oc="${__tca_st[OptionChar]:--}"
    local __tca_ocn=${#__tca_oc}
    local __tca_cs="${__tca_st[CaseSensitiveOptions]:-true}"
    local __tca_n="${__tca_st[_ARGC]:-0}"
    local __tca_so="$__tca_name" __tca_o

    __TCA_IDX=-1
    __TCA_LONG=0
    if (( __tca_ocn == 0 )); then
        return 0
    fi
    if [[ "$__tca_cs" != "true" ]]; then
        __tca_so="${__tca_so^^}"
    fi
    if (( __tca_i == -1 )); then
        __tca_i=$__tca_n
    fi
    if (( __tca_i > __tca_n )); then
        __tca_i=$__tca_n
    fi

    while (( __TCA_IDX == -1 && __tca_i > 0 )); do
        __tca_o="${__tca_st[_ARG_$__tca_i]:-}"
        # `-` alone must be seen as an option VALUE, not an option (FPC:
        # `If (Length(O)>1) and (O[1]=FOptionChar)`).
        if (( ${#__tca_o} > __tca_ocn )) && [[ "${__tca_o:0:__tca_ocn}" == "$__tca_oc" ]]; then
            __tca_o="${__tca_o:__tca_ocn}"
            if [[ "${__tca_o:0:__tca_ocn}" == "$__tca_oc" ]]; then
                __TCA_LONG=1
                __tca_o="${__tca_o:__tca_ocn}"
                # Long options have the form --name=value; the name stops at `=`.
                if [[ "$__tca_o" == *=* ]]; then
                    __tca_o="${__tca_o%%=*}"
                fi
            else
                __TCA_LONG=0
            fi
            if [[ "$__tca_cs" != "true" ]]; then
                __tca_o="${__tca_o^^}"
            fi
            if [[ "$__tca_o" == "$__tca_so" ]]; then
                __TCA_IDX=$__tca_i
            fi
        fi
        (( __tca_i -= 1 )) || :
    done
    return 0
}

# ----------------------------------------------------------------------------
# tca._optionAt DATA INDEX IS_LONG — FPC `GetOptionAtIndex`.
#   long  : the text after the first `=` in the argument itself; no `=` means
#           no value (FPC deletes Length(O) characters), so `--out file` is ''.
#   short : the NEXT argument, unless it starts with OptionChar. An empty next
#           argument is a value (FPC compares Copy(...,1,1) with OptionChar).
#   -> __TCA_VAL
# ----------------------------------------------------------------------------
tca._optionAt() {
    local -n __tca_st="$1"
    local __tca_i="$2" __tca_long="$3"
    local __tca_oc="${__tca_st[OptionChar]:--}"
    local __tca_n="${__tca_st[_ARGC]:-0}"
    local __tca_o

    __TCA_VAL=""
    if (( __tca_i == -1 )); then
        return 0
    fi
    if (( __tca_long )); then
        __tca_o="${__tca_st[_ARG_$__tca_i]:-}"
        if [[ "$__tca_o" == *=* ]]; then
            __TCA_VAL="${__tca_o#*=}"
        fi
    elif (( __tca_i < __tca_n )); then
        __tca_o="${__tca_st[_ARG_$((__tca_i + 1))]:-}"
        if [[ "${__tca_o:0:${#__tca_oc}}" != "$__tca_oc" ]]; then
            __TCA_VAL="$__tca_o"
        fi
    fi
    return 0
}

# ----------------------------------------------------------------------------
# tca._longOpts SPEC OUTARRAY — FPC has one CheckOptions overload taking a
# TStrings and one taking a space/tab/CR/LF separated string. Which one a bash
# call means is decided by SPEC alone (finding TCA-08): the NAME of an existing
# array variable is that array, anything else is the separated string.
# ----------------------------------------------------------------------------
tca._longOpts() {
    local __tca_spec="${1:-}"
    local -n __tca_out="$2"
    local __tca_rest __tca_tok __tca_lead

    __tca_out=()
    if [[ -z "$__tca_spec" ]]; then
        return 0
    fi

    case "$__tca_spec" in
        ""|*[!A-Za-z0-9_]*|[0-9]*) ;;
        *)  if declare -p "$__tca_spec" >/dev/null 2>&1; then
                local -n __tca_src="$__tca_spec"
                case "${__tca_src@a}" in
                    *[aA]*) __tca_out=("${__tca_src[@]}"); return 0 ;;
                esac
            fi
            ;;
    esac

    # FPC SepChars = ' '#10#13#9. Split by hand: `read -ra` stops at the first
    # newline and an unquoted expansion would glob a long option named `*`.
    __tca_rest="${__tca_spec//$'\t'/ }"
    __tca_rest="${__tca_rest//$'\n'/ }"
    __tca_rest="${__tca_rest//$'\r'/ }"
    while [[ -n "$__tca_rest" ]]; do
        __tca_lead="${__tca_rest%%[! ]*}"
        __tca_rest="${__tca_rest#"$__tca_lead"}"
        if [[ -z "$__tca_rest" ]]; then
            break
        fi
        __tca_tok="${__tca_rest%%' '*}"
        __tca_out+=("$__tca_tok")
        __tca_rest="${__tca_rest#"$__tca_tok"}"
    done
    return 0
}

# tca._findLongOpt ARRAYNAME NEEDLE CASESENSITIVE — FPC's nested FindLongOpt:
# a downward exact scan, upper-cased on both sides when case is ignored.
tca._findLongOpt() {
    local -n __tca_l="$1"
    local __tca_s="$2" __tca_cs="$3" __tca_j __tca_e

    if [[ "$__tca_cs" != "true" ]]; then
        __tca_s="${__tca_s^^}"
    fi
    for (( __tca_j = ${#__tca_l[@]} - 1; __tca_j >= 0; __tca_j-- )); do
        __tca_e="${__tca_l[__tca_j]}"
        if [[ "$__tca_cs" != "true" ]]; then
            __tca_e="${__tca_e^^}"
        fi
        if [[ "$__tca_e" == "$__tca_s" ]]; then
            return 0
        fi
    done
    return 1
}

# tca._addErr FMT ARGS... — FPC's nested AddToResult, appending to the caller's
# `__tca_res` (bash scopes locals dynamically). sLineBreak is a plain newline.
tca._addErr() {
    local __tca_m
    printf -v __tca_m "$@"
    if [[ -n "$__tca_res" ]]; then
        __tca_res+=$'\n'
    fi
    __tca_res+="$__tca_m"
}

# ----------------------------------------------------------------------------
# tca._checkOptions DATA LONGARR SHORTOPTS ALLERRORS OPTSVAR NONOPTSVAR
#
# FPC `CheckOptions(ShortOptions, Longopts, Opts, NonOpts, AllErrors)`.
#   * `x`  in ShortOptions / `name`   in LongOpts — switch, no argument;
#   * `x:` in ShortOptions / `name:`  in LongOpts — argument REQUIRED;
#   * `x::`in ShortOptions / `name::` in LongOpts — argument optional.
# A long option's value is written `--name=value` and nothing else; a short
# option's value is the next argument, and it is consumed (the loop skips it).
# A short option that takes an argument must be LAST in a cluster.
#   -> __TCA_ERR = '' or the error message(s), joined with newlines
# ----------------------------------------------------------------------------
tca._checkOptions() {
    local -n __tca_st="$1"
    local __tca_larr="$2" __tca_short="$3" __tca_all="$4"
    local __tca_optsv="$5" __tca_nonv="$6"

    local __tca_oc="${__tca_st[OptionChar]:--}"
    local __tca_ocn=${#__tca_oc}
    local __tca_cs="${__tca_st[CaseSensitiveOptions]:-true}"
    local __tca_n="${__tca_st[_ARGC]:-0}"
    local __tca_so="$__tca_short"
    local __tca_res="" __tca_i=1
    local __tca_o __tca_ov __tca_oadd __tca_next __tca_ch __tca_pre
    local __tca_have __tca_used __tca_l __tca_j __tca_p
    local -a __tca_acc_opts=() __tca_acc_non=()

    if [[ "$__tca_cs" != "true" ]]; then
        __tca_so="${__tca_so,,}"
    fi

    while (( __tca_i <= __tca_n )); do
        if [[ -n "$__tca_res" && "$__tca_all" != "true" ]]; then
            break
        fi
        __tca_o="${__tca_st[_ARG_$__tca_i]:-}"

        if (( ${#__tca_o} == 0 )) || [[ "${__tca_o:0:__tca_ocn}" != "$__tca_oc" ]]; then
            __tca_acc_non+=("$__tca_o")
        elif (( ${#__tca_o} <= __tca_ocn )); then
            # A bare `-` is an option that is too short to name anything.
            tca._addErr 'Invalid option at position %d: "%s"' "$__tca_i" "$__tca_o"
        else
            __tca_have=0
            __tca_ov=""
            if [[ "${__tca_o:__tca_ocn:__tca_ocn}" == "$__tca_oc" ]]; then
                # ---- long option ------------------------------------------
                __tca_o="${__tca_o:2 * __tca_ocn}"
                if [[ "$__tca_o" == *=* ]]; then
                    __tca_have=1
                    __tca_ov="${__tca_o#*=}"
                    __tca_o="${__tca_o%%=*}"
                fi
                __tca_oadd="$__tca_o"
                if tca._findLongOpt "$__tca_larr" "$__tca_o" "$__tca_cs"; then
                    if (( __tca_have )); then
                        tca._addErr 'Option at position %d does not allow an argument: %s' \
                            "$__tca_i" "$__tca_o"
                    fi
                elif tca._findLongOpt "$__tca_larr" "$__tca_o:" "$__tca_cs"; then
                    if (( ! __tca_have )); then
                        tca._addErr 'Option at position %d needs an argument : %s' \
                            "$__tca_i" "$__tca_o"
                    fi
                elif ! tca._findLongOpt "$__tca_larr" "$__tca_o::" "$__tca_cs"; then
                    tca._addErr 'Invalid option at position %d: "%s"' "$__tca_i" "$__tca_o"
                fi
            else
                # ---- short option, possibly a cluster ---------------------
                if (( __tca_i < __tca_n )); then
                    __tca_next="${__tca_st[_ARG_$((__tca_i + 1))]:-}"
                    if (( ${#__tca_next} > 0 )) && [[ "${__tca_next:0:__tca_ocn}" != "$__tca_oc" ]]; then
                        __tca_have=1
                    fi
                fi
                __tca_used=0
                if [[ "$__tca_cs" != "true" ]]; then
                    __tca_o="${__tca_o,,}"
                fi
                __tca_oadd="$__tca_o"
                __tca_l=${#__tca_o}
                __tca_j=$(( __tca_ocn + 1 ))
                while (( __tca_j <= __tca_l )); do
                    if [[ -n "$__tca_res" && "$__tca_all" != "true" ]]; then
                        break
                    fi
                    __tca_ch="${__tca_o:__tca_j - 1:1}"
                    __tca_p=0
                    if [[ -n "$__tca_ch" && "$__tca_so" == *"$__tca_ch"* ]]; then
                        __tca_pre="${__tca_so%%"$__tca_ch"*}"
                        __tca_p=$(( ${#__tca_pre} + 1 ))
                    fi
                    if (( __tca_p == 0 )) || [[ "$__tca_ch" == ":" ]]; then
                        tca._addErr 'Invalid option at position %d: "%s"' "$__tca_i" "$__tca_ch"
                    elif (( __tca_p < ${#__tca_so} )) && [[ "${__tca_so:__tca_p:1}" == ":" ]]; then
                        # `x:` = required, `x::` = optional.
                        if (( __tca_p + 1 == ${#__tca_so} )) || [[ "${__tca_so:__tca_p + 1:1}" != ":" ]]; then
                            if (( __tca_j < __tca_l )) || (( ! __tca_have )); then
                                # Must be last in a multi-option argument.
                                tca._addErr 'Option at position %d needs an argument : %s' \
                                    "$__tca_i" "$__tca_ch"
                            fi
                        fi
                        __tca_oadd="$__tca_ch"
                        __tca_used=1
                    fi
                    (( __tca_j += 1 )) || :
                done
                if (( ! __tca_used )); then
                    __tca_have=0
                fi
                if (( __tca_have )); then
                    (( __tca_i += 1 )) || :           # skip the consumed value
                    __tca_ov="${__tca_st[_ARG_$__tca_i]:-}"
                fi
            fi
            if (( __tca_have )) && { [[ -z "$__tca_res" ]] || [[ "$__tca_all" == "true" ]]; }; then
                __tca_acc_opts+=("$__tca_oadd=$__tca_ov")
            fi
        fi
        (( __tca_i += 1 )) || :
    done

    if [[ -n "$__tca_optsv" ]]; then
        local -n __tca_optsr="$__tca_optsv"
        __tca_optsr=("${__tca_acc_opts[@]}")
    fi
    if [[ -n "$__tca_nonv" ]]; then
        local -n __tca_nonr="$__tca_nonv"
        __tca_nonr=("${__tca_acc_non[@]}")
    fi
    __TCA_ERR="$__tca_res"
    return 0
}

# ============================================================================
# TCustomApplication — interface (structure)
# ============================================================================
class TCustomApplication
    public
        constructor Create

        # Published, stored properties
        var Terminated
        var Title
        var HelpFile
        var OptionChar
        var CaseSensitiveOptions
        var StopOnException
        var ExceptionExitCode
        var OnException
        var EventLogFilter

        # Computed (read-only) property
        property ExeName read _getExeName

        # Lifecycle / argument handling
        proc Initialize
        proc SetArgs
        func _GetArgs

        # Option parsing
        func FindOptionIndex
        func GetOptionAtIndex
        func GetOptionValue
        func GetOptionValues
        func HasOption
        func CheckOptions
        func GetNonOptions

        # Run / termination / exceptions
        proc Terminate
        proc DoRun
        proc Run
        proc HandleException
        proc ShowException

        # Environment / logging
        func GetEnvironmentList
        proc Log

        # Application info
        func _getExeName
        func ConsoleApplication
        func Location
        func ParamCount
        func Params
        func EnvironmentVariable
end

# ============================================================================
# TCustomApplication — implementation (real bash bodies)
# ============================================================================

TCustomApplication.Create() {
    Terminated="false"
    Title="Application"
    HelpFile=""
    OptionChar="-"
    CaseSensitiveOptions="true"
    StopOnException="true"
    ExceptionExitCode="1"
    OnException=""
    EventLogFilter=""
    state["_ARGC"]="0"

    # `Create "$@"` is the documented way to hand a script's real command line
    # to the instance. Nothing is auto-captured otherwise: the old build stored
    # the FIRST OPTION METHOD's own parameters as the application's argv
    # (finding TCA-04), which made `a.GetNonOptions "" "" nn` answer 3.
    if (( $# > 0 )); then
        $this.SetArgs "$@"
    fi
}

TCustomApplication.Initialize() {
    Terminated="false"
}

# SetArgs ARG... — store the application's argument vector verbatim. The
# arguments are Params[1..N]; Params[0] stays the executable name ($0), exactly
# as ParamStr numbers them in FPC. There is no `--` separator any more: a
# leading `--` used to be swallowed silently (finding TCA-13), so `SetArgs --`
# could not pass `--` on to the parser at all.
TCustomApplication.SetArgs() {
    local __tca_old="${state[_ARGC]:-0}" __tca_i __tca_a

    for (( __tca_i = 1; __tca_i <= __tca_old; __tca_i++ )); do
        unset "state[_ARG_$__tca_i]"
    done

    __tca_i=0
    for __tca_a in "$@"; do
        (( __tca_i += 1 )) || :
        state["_ARG_$__tca_i"]="$__tca_a"
    done
    state["_ARGC"]="$__tca_i"
}

# _GetArgs — the stored argument count. Kept as an alias of ParamCount because
# the suite and existing callers use it.
TCustomApplication._GetArgs() {
    RESULT="${state[_ARGC]:-0}"
}

TCustomApplication.ParamCount() {
    RESULT="${state[_ARGC]:-0}"
}

# Params INDEX — FPC `Params[Index] = ParamStr(Index)`: index 0 is the
# executable name, 1..ParamCount the arguments, anything else ''.
TCustomApplication.Params() {
    local __tca_i="${1:-}" __tca_n
    if ! kk.isInt "$__tca_i" __tca_i; then
        kk._return ""
        return 1
    fi
    __tca_n="${state[_ARGC]:-0}"
    if (( __tca_i == 0 )); then
        RESULT="$0"
    elif (( __tca_i >= 1 && __tca_i <= __tca_n )); then
        RESULT="${state[_ARG_$__tca_i]:-}"
    else
        RESULT=""
    fi
}

# FindOptionIndex SHORT LONG [START_AT] — FPC calls FindOptionIndex once per
# name; this port carries the (short, long) pair through its whole option API,
# so it is FPC's composition: the short name first, the long name only if the
# short one was not found. An empty name is "not given" and is not searched
# (FPC passes the impossible char #255 for exactly that).
TCustomApplication.FindOptionIndex() {
    local __tca_short="${1:-}" __tca_long="${2:-}" __tca_start="${3:--1}"

    # TCA-05 (X-INJ, D1): start_at reaches the loop arithmetic.
    if ! kk.isInt "$__tca_start" __tca_start; then
        kk._return ""
        return 1
    fi

    __TCA_IDX=-1
    if [[ -n "$__tca_short" ]]; then
        tca._findIndex "${this}_data" "$__tca_short" "$__tca_start"
    fi
    if (( __TCA_IDX == -1 )) && [[ -n "$__tca_long" ]]; then
        tca._findIndex "${this}_data" "$__tca_long" "$__tca_start"
    fi
    RESULT="$__TCA_IDX"
}

# GetOptionAtIndex INDEX IS_LONG — FPC's protected GetOptionAtIndex, exposed
# because the (short, long) merge above hides which form matched.
TCustomApplication.GetOptionAtIndex() {
    local __tca_i="${1:-}" __tca_long="${2:-false}" __tca_lf=0
    if ! kk.isInt "$__tca_i" __tca_i; then
        kk._return ""
        return 1
    fi
    case "$__tca_long" in
        true|TRUE|True|1) __tca_lf=1 ;;
    esac
    tca._optionAt "${this}_data" "$__tca_i" "$__tca_lf"
    RESULT="$__TCA_VAL"
}

# GetOptionValue SHORT LONG — FPC: short name first, then the long one; the
# value comes from GetOptionAtIndex, so a long option only has a value when it
# was written `--name=value`.
TCustomApplication.GetOptionValue() {
    local __tca_short="${1:-}" __tca_long="${2:-}"
    local __tca_i=-1 __tca_lng=0

    if [[ -n "$__tca_short" ]]; then
        tca._findIndex "${this}_data" "$__tca_short" -1
        __tca_i=$__TCA_IDX
        __tca_lng=$__TCA_LONG
    fi
    if (( __tca_i == -1 )) && [[ -n "$__tca_long" ]]; then
        tca._findIndex "${this}_data" "$__tca_long" -1
        __tca_i=$__TCA_IDX
        __tca_lng=$__TCA_LONG
    fi

    __TCA_VAL=""
    if (( __tca_i != -1 )); then
        tca._optionAt "${this}_data" "$__tca_i" "$__tca_lng"
    fi
    RESULT="$__TCA_VAL"
}

# GetOptionValues SHORT LONG [OUTARRAY] — every value of the option, count in
# RESULT (default R10 / kcl README 1.7). FPC collects the short matches first
# and the long ones after, each by scanning DOWNWARD, so the values come back
# in reverse command-line order; that is the upstream algorithm, not a bug of
# the port. The old `"count:v1 v2"` string could not represent a value with a
# space in it (finding TCA-07).
TCustomApplication.GetOptionValues() {
    local __tca_short="${1:-}" __tca_long="${2:-}" __tca_out="${3:-}"
    local __tca_i
    local -a __tca_vals=()

    if [[ -n "$__tca_out" ]] && ! tca._outName "$__tca_out" "$this"; then
        kk._return ""
        return 2
    fi

    if [[ -n "$__tca_short" ]]; then
        __tca_i=-1
        while : ; do
            tca._findIndex "${this}_data" "$__tca_short" "$__tca_i"
            __tca_i=$__TCA_IDX
            if (( __tca_i == -1 )); then
                break
            fi
            tca._optionAt "${this}_data" "$__tca_i" 0
            __tca_vals+=("$__TCA_VAL")
            (( __tca_i -= 1 )) || :
        done
    fi
    if [[ -n "$__tca_long" ]]; then
        __tca_i=-1
        while : ; do
            tca._findIndex "${this}_data" "$__tca_long" "$__tca_i"
            __tca_i=$__TCA_IDX
            if (( __tca_i == -1 )); then
                break
            fi
            tca._optionAt "${this}_data" "$__tca_i" 1
            __tca_vals+=("$__TCA_VAL")
            (( __tca_i -= 1 )) || :
        done
    fi

    if [[ -n "$__tca_out" ]]; then
        local -n __tca_outref="$__tca_out"
        __tca_outref=("${__tca_vals[@]}")
    fi
    RESULT="${#__tca_vals[@]}"
}

# HasOption SHORT LONG — a predicate: the answer is the EXIT STATUS
# (kcl/README.md 1.3); `true`/`false` is also left in RESULT so the older
# `[[ "$(a.HasOption v '')" == true ]]` form keeps working (default R8).
TCustomApplication.HasOption() {
    local __tca_short="${1:-}" __tca_long="${2:-}" __tca_found=0

    if [[ -n "$__tca_short" ]]; then
        tca._findIndex "${this}_data" "$__tca_short" -1
        if (( __TCA_IDX != -1 )); then
            __tca_found=1
        fi
    fi
    if (( ! __tca_found )) && [[ -n "$__tca_long" ]]; then
        tca._findIndex "${this}_data" "$__tca_long" -1
        if (( __TCA_IDX != -1 )); then
            __tca_found=1
        fi
    fi

    if (( __tca_found )); then
        kk._return "true"
        return 0
    fi
    kk._return "false"
    return 1
}

# CheckOptions SHORT LONG [OPTS|ALLERRORS] [NONOPTS] [ALLERRORS]
#   SHORT      — getopt-style short option string, `:` / `::` for values
#   LONG       — the name of an array of long options, or a separated string
#   OPTS       — name of an array to receive `name=value` for every option that
#                actually took a value (FPC only adds those)
#   NONOPTS    — name of an array to receive the non-option arguments
#   ALLERRORS  — `true` keeps going and joins every error with a newline
# RESULT is FPC's function result: '' or the error message(s).
TCustomApplication.CheckOptions() {
    local __tca_short="${1:-}" __tca_long="${2:-}"
    local __tca_p3="${3:-}" __tca_p4="${4:-}" __tca_p5="${5:-false}"
    local __tca_optsv="" __tca_nonv="" __tca_all="false"
    local -a __tca_longs=()

    # FPC overloads on the parameter list; bash decides on the value: a third
    # parameter that is exactly `true`/`false` is AllErrors.
    if [[ "$__tca_p3" == "true" || "$__tca_p3" == "false" ]]; then
        __tca_all="$__tca_p3"
    else
        __tca_optsv="$__tca_p3"
        __tca_nonv="$__tca_p4"
        __tca_all="$__tca_p5"
    fi

    if [[ -n "$__tca_optsv" ]] && ! tca._outName "$__tca_optsv" "$this"; then
        kk._return ""
        return 2
    fi
    if [[ -n "$__tca_nonv" ]] && ! tca._outName "$__tca_nonv" "$this"; then
        kk._return ""
        return 2
    fi

    tca._longOpts "$__tca_long" __tca_longs
    tca._checkOptions "${this}_data" __tca_longs "$__tca_short" "$__tca_all" \
        "$__tca_optsv" "$__tca_nonv"
    RESULT="$__TCA_ERR"
}

# GetNonOptions SHORT LONG [OUTARRAY] — FPC runs CheckOptions with AllErrors
# and RAISES EListError when anything was wrong; the bash contract for that is
# rc 1 with RESULT='' and the output array untouched (D2).
TCustomApplication.GetNonOptions() {
    local __tca_short="${1:-}" __tca_long="${2:-}" __tca_out="${3:-}"
    local -a __tca_longs=() __tca_non=()

    if [[ -n "$__tca_out" ]] && ! tca._outName "$__tca_out" "$this"; then
        kk._return ""
        return 2
    fi

    tca._longOpts "$__tca_long" __tca_longs
    tca._checkOptions "${this}_data" __tca_longs "$__tca_short" "true" "" "__tca_non"

    if [[ -n "$__TCA_ERR" ]]; then
        if [[ "${VERBOSE_KKLASS:-}" == "debug" ]]; then
            printf '%s\n' "Error: GetNonOptions: $__TCA_ERR" >&2
        fi
        kk._return ""
        return 1
    fi

    if [[ -n "$__tca_out" ]]; then
        local -n __tca_outref="$__tca_out"
        __tca_outref=("${__tca_non[@]}")
    fi
    RESULT="${#__tca_non[@]}"
}

# Terminate [EXITCODE] — FPC sets FTerminated and the program's global ExitCode.
# EXITCODE is a plain global here, NOT exported: the old build put it in the
# environment of every child process (finding TCA-12).
TCustomApplication.Terminate() {
    local __tca_code="${1:-}"
    Terminated="true"
    if [[ -n "$__tca_code" ]]; then
        if ! kk.isInt "$__tca_code" __tca_code; then
            return 1
        fi
        declare -g EXITCODE="$__tca_code"
    fi
    return 0
}

# DoRun — FPC's DoRun is empty and descendants override it; an empty DoRun here
# would make Run spin forever, so the base class terminates after one pass.
TCustomApplication.DoRun() {
    $this.Terminate
}

# Run — FPC: `Repeat Try DoRun except HandleException(Self) end Until Terminated`.
# bash has no exceptions, so a non-zero status from DoRun is what HandleException
# is given. No forks, no sleep, no busy loop: the old build ran `$( )` plus
# `sleep 0.01` per iteration and could not be stopped (finding TCA-10).
TCustomApplication.Run() {
    while : ; do
        $this.DoRun || $this.HandleException "$this" "DoRun returned a non-zero status"
        if [[ "$Terminated" == "true" ]]; then
            break
        fi
    done
    return 0
}

TCustomApplication.HandleException() {
    local __tca_sender="${1:-}" __tca_msg="${2:-}"

    # TCA-20: `OnException = "my handler"` used to reach the shell as a command.
    if [[ -n "$OnException" ]] && declare -F "$OnException" >/dev/null 2>&1; then
        "$OnException" "$__tca_sender" "$__tca_msg" || :
    else
        if [[ -n "$OnException" && "${VERBOSE_KKLASS:-}" == "debug" ]]; then
            printf '%s\n' "Error: HandleException: OnException '$OnException' is not a function" >&2
        fi
        $this.ShowException "$__tca_msg"
    fi

    if [[ "$StopOnException" == "true" ]]; then
        $this.Terminate "$ExceptionExitCode"
    fi
    return 0
}

TCustomApplication.ShowException() {
    local __tca_msg="${1:-}"
    if [[ -n "$__tca_msg" ]]; then
        printf '%s\n' "Exception: $__tca_msg" >&2
    fi
    return 0
}

# GetEnvironmentList OUTARRAY [NAMESONLY] — FPC's SysGetEnvironmentList.
# `compgen -e` instead of `env | sort` (finding TCA-15): the value is read with
# ${!name}, so a value containing newlines stays ONE entry instead of becoming
# several bogus ones, and nothing is re-sorted (FPC does not sort either).
# RESULT = the number of entries.
TCustomApplication.GetEnvironmentList() {
    local __tca_out="${1:-}" __tca_names="${2:-false}" __tca_v __tca_i=0
    local -a __tca_env=()

    if ! tca._outName "$__tca_out" "$this"; then
        kk._return ""
        return 2
    fi
    local -n __tca_ref="$__tca_out"
    __tca_ref=()

    readarray -t __tca_env < <(compgen -e)
    for __tca_v in "${__tca_env[@]}"; do
        case "$__tca_v" in
            ""|*[!A-Za-z0-9_]*|[0-9]*) continue ;;
        esac
        if [[ "$__tca_names" == "true" ]]; then
            __tca_ref[__tca_i]="$__tca_v"
        else
            __tca_ref[__tca_i]="$__tca_v=${!__tca_v:-}"
        fi
        (( __tca_i += 1 )) || :
    done
    RESULT="$__tca_i"
}

# Log EVENTTYPE FMT [ARGS...] — FPC's `Log(EventType, Fmt, Args)`: the message
# is formatted, then the filter decides. EventLogFilter is a space- or
# comma-separated set of event types and membership is EXACT; empty means "log
# everything". Output goes to stderr — FPC's DoLog is empty and descendants
# override it, but a log line is a diagnostic, not the program's output
# (finding TCA-16: format arguments were dropped, the filter was a substring
# match and the line went to stdout).
TCustomApplication.Log() {
    local __tca_type="${1:-}" __tca_fmt="${2:-}" __tca_msg __tca_filter
    if (( $# > 2 )); then
        shift 2
    else
        set --
    fi

    __tca_msg="$__tca_fmt"
    if (( $# > 0 )); then
        if ! printf -v __tca_msg "$__tca_fmt" "$@" 2>/dev/null; then
            printf -v __tca_msg 'Error formatting message "%s" with %d arguments' \
                "$__tca_fmt" "$#"
            __tca_type="etError"
        fi
    fi

    if [[ -n "$EventLogFilter" ]]; then
        __tca_filter=" ${EventLogFilter//,/ } "
        if [[ "$__tca_filter" != *" $__tca_type "* ]]; then
            return 0
        fi
    fi
    printf '%s: %s\n' "$__tca_type" "$__tca_msg" >&2
    return 0
}

TCustomApplication._getExeName() {
    # FPC: ParamStr(0).
    RESULT="$0"
}

TCustomApplication.ConsoleApplication() {
    # FPC: IsConsole. A bash script always is one.
    RESULT="true"
}

# Location — FPC `ExtractFilePath(ParamStr(0))`, i.e. the directory of the
# RUNNING SCRIPT. The old build read BASH_SOURCE[0], which inside an eval'd
# kklass method body is kklass.sh (finding TCA-11). No trailing separator, to
# match tpath.getDirectoryName and the rest of kcl.
TCustomApplication.Location() {
    local __tca_p="${0//\\//}"
    if [[ "$__tca_p" == */* ]]; then
        RESULT="${__tca_p%/*}"
        if [[ -z "$RESULT" ]]; then
            RESULT="/"
        fi
    else
        RESULT="."
    fi
}

TCustomApplication.EnvironmentVariable() {
    # TCA-05 (X-INJ): `${!var_name}` performs ARITHMETIC evaluation on an array
    # subscript, so `EnvironmentVariable 'x[$(touch pwn)]'` ran the command; a
    # name like 'not valid' printed a raw bash error with rc 0, and '@' returned
    # the positional parameters. Only a plain identifier is a variable name.
    local __tca_name="${1:-}"
    case "$__tca_name" in
        ""|*[!A-Za-z0-9_]*|[0-9]*)
            if [[ "${VERBOSE_KKLASS:-}" == "debug" ]]; then
                printf '%s\n' "Error: EnvironmentVariable: '$__tca_name' is not a variable name" >&2
            fi
            kk._return ""
            return 1
            ;;
    esac
    RESULT="${!__tca_name:-}"
}

build TCustomApplication
