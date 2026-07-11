#!/bin/bash

# Source kklass system (don't override SCRIPT_DIR)
TCUSTOMAPPLICATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TCUSTOMAPPLICATION_DIR/../../kklass/kklass_pascal.sh"
source "$TCUSTOMAPPLICATION_DIR/../../kkore/kuse.sh"
unset -f tcustomapplication._call_silent 2>/dev/null || true

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
        proc _EnsureArgsInitialized
        proc _PrepareArguments

        # Option parsing
        func _GetArgs
        func _GetNextArgValue
        func FindOptionIndex
        func GetOptionValue
        func GetOptionValues
        func HasOption
        func _ValidateOption
        func _ParseLongOpts
        func CheckOptions
        func GetNonOptions

        # Run / termination / exceptions
        proc Terminate
        proc Run
        proc HandleException
        proc ShowException

        # Environment / logging
        proc GetEnvironmentList
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
    # Initialize all properties to default values
    Terminated="false"
    Title="Application"
    HelpFile=""
    OptionChar="-"
    CaseSensitiveOptions="true"
    StopOnException="true"
    ExceptionExitCode="1"
    OnException=""
    EventLogFilter=""
    # Initialize command-line arguments storage as empty array
    state["_TCUSTAPP_ARGS_COUNT"]="0"
    # Initialize cache for getopts string conversion
    state["_CachedShortOpts"]=""
    state["_CachedGetoptOpts"]=""
    # Initialize cache flag for arguments initialization
    state["_ArgsInitialized"]="false"
    # Cache OptionChar for performance
    state["_OptionCharCache"]="-"
    state["_DoubleOptionCharCache"]="--"

    # Initialize arguments from script parameters if any provided
    if [[ $# -gt 0 ]]; then
        $this.SetArgs "$@"
    fi
}

TCustomApplication.Initialize() {
    # Initialize sets Terminated to false
    Terminated="false"
}

TCustomApplication.SetArgs() {
    # Store command-line arguments for this instance in the instance data
    # Clear existing arguments first
    local old_count="${state[_TCUSTAPP_ARGS_COUNT]:-0}"
    local i
    for ((i = 0; i < old_count; i++)); do
        unset "state[_TCUSTAPP_ARG_$i]"
    done
    state["_TCUSTAPP_ARGS_COUNT"]="0"

    # Initialize cache variables if not already done
    if [[ -z "${state[_CachedShortOpts]:-}" ]]; then
        state["_CachedShortOpts"]=""
        state["_CachedGetoptOpts"]=""
    fi

    # Handle -- separator: if first argument is --, skip it
    local start_index=1
    if [[ "$1" == "--" ]]; then
        start_index=2
    fi

    # Store each argument without shell escaping - use a safer approach
    local arg_index=0
    for ((i = start_index; i <= $#; i++)); do
        # Get argument by position using indirect expansion
        local arg="${!i}"
        # Store arguments as-is, preserving their original form
        state["_TCUSTAPP_ARG_$arg_index"]="$arg"
        ((arg_index++))
    done
    state["_TCUSTAPP_ARGS_COUNT"]="$arg_index"

    # Mark arguments as initialized
    state["_ArgsInitialized"]="true"
}

TCustomApplication._EnsureArgsInitialized() {
    # Auto-initialize arguments from script parameters if not already done
    # This is called automatically from functions that need arguments
    if [[ "${state[_ArgsInitialized]:-false}" == "false" ]]; then
        local old_count="${state[_TCUSTAPP_ARGS_COUNT]:-0}"
        local i
        for ((i = 0; i < old_count; i++)); do
            unset "state[_TCUSTAPP_ARG_$i]"
        done

        local arg_index=0
        for arg in "$@"; do
            state["_TCUSTAPP_ARG_$arg_index"]="$arg"
            ((arg_index++))
        done
        state["_TCUSTAPP_ARGS_COUNT"]="$arg_index"
        state["_ArgsInitialized"]="true"
    fi
}

TCustomApplication._PrepareArguments() {
    # Internal helper: Initialize arguments and setup common variables.
    # Skip the _EnsureArgsInitialized method dispatch once args are already
    # initialized (the common case after SetArgs) — this is what made
    # GetOptionValues O(n*k) as it loops FindOptionIndex. The OptionChar
    # caches are recomputed cheaply so a mutated OptionChar stays correct.
    if [[ "${state[_ArgsInitialized]:-false}" != "true" ]]; then
        $this.call _EnsureArgsInitialized "$@"
    fi

    state["_OptionCharCache"]="$OptionChar"
    state["_DoubleOptionCharCache"]="$OptionChar$OptionChar"
}

TCustomApplication._GetArgs() {
    # Get stored arguments array
    # Return count of arguments
    RESULT="${state[_TCUSTAPP_ARGS_COUNT]:-0}"
}

TCustomApplication._GetNextArgValue() {
    local idx="$1"
    local args_count="${state[_TCUSTAPP_ARGS_COUNT]:-0}"

    if [[ $((idx + 1)) -lt $args_count ]]; then
        local next_arg="${state[_TCUSTAPP_ARG_$((idx + 1))]}"
        if [[ ! "$next_arg" =~ ^- ]]; then
            RESULT="$next_arg"
            kk._return "$RESULT"
            return 0
        fi
    fi

    RESULT=""
    kk._return "$RESULT"
    return 1
}

TCustomApplication.FindOptionIndex() {
    local short_opt="$1"
    local long_opt="${2:-}"
    local start_at="${3:--1}"

    # Prepare arguments and common variables
    $this.call _PrepareArguments "$@"

    # Get the current OptionChar
    local opt_char="${state[_OptionCharCache]:-$OptionChar}"
    local args_count="${state[_TCUSTAPP_ARGS_COUNT]:-0}"

    # Search for option in arguments starting from start_at
    local search_start=0
    [[ "$start_at" -ge 0 ]] && search_start="$start_at"

    local i
    for ((i = search_start; i < args_count; i++)); do
        local arg="${state[_TCUSTAPP_ARG_$i]}"

        # Check short option (single char with option char prefix)
        if [[ -n "$short_opt" && "$arg" == "$opt_char$short_opt" ]]; then
            RESULT="$i"
            kk._return "$RESULT"
            return 0
        fi

        # Check long option (with double option char prefix)
        if [[ -n "$long_opt" && "$arg" == "$opt_char$opt_char$long_opt" ]]; then
            RESULT="$i"
            kk._return "$RESULT"
            return 0
        fi
    done

    RESULT="-1"
}

TCustomApplication.GetOptionValue() {
    local opt="$1"
    local secondary_opt="${2:-}"

    # Prepare arguments and common variables
    $this.call _PrepareArguments "$@"

    # Find option using FindOptionIndex (checks both short and long options in one call)
    local idx
    kk.call_silent "$this" FindOptionIndex "$opt" "$secondary_opt" -1
    idx="$RESULT"

    if [[ "$idx" -ge 0 ]]; then
        kk.call_silent "$this" _GetNextArgValue "$idx"
        if [[ $? -eq 0 ]]; then
            kk._return "$RESULT"
            return 0
        fi
    fi

    RESULT=""
}

TCustomApplication.GetOptionValues() {
    local short_opt="$1"
    local long_opt="${2:-}"

    # Prepare arguments and common variables
    $this.call _PrepareArguments "$@"

    # OPTIMIZATION 2: Pre-allocate array with proper capacity to avoid reallocations
    local -a values
    local value_count=0

    # Collect all values for this option
    local i=0
    while true; do
        local idx
        kk.call_silent "$this" FindOptionIndex "$short_opt" "$long_opt" "$i"
        idx="$RESULT"

        if [[ "$idx" -lt 0 ]]; then
            break
        fi

        kk.call_silent "$this" _GetNextArgValue "$idx"
        if [[ $? -eq 0 ]]; then
            values[value_count]="$RESULT"
            ((value_count++))
        fi

        i=$((idx + 1))
    done

    # Return array count and values
    if [[ $value_count -gt 0 ]]; then
        RESULT="$value_count:${values[*]}"
    else
        RESULT="0:"
    fi
}

TCustomApplication.HasOption() {
    local opt="$1"
    local secondary_opt="${2:-}"

    # Prepare arguments and common variables
    $this.call _PrepareArguments "$@"

    local idx
    kk.call_silent "$this" FindOptionIndex "$opt" "$secondary_opt" -1
    idx="$RESULT"

    if [[ "$idx" -ge 0 ]]; then
        RESULT="true"
    else
        RESULT="false"
    fi
}

TCustomApplication._ValidateOption() {
    # Validate and process option(s) - works for both short and long options
    # Input: $1 = option(s) to validate, $2 = option type ("short" or "long")
    #        $3 = allowed options (string for short, space-separated for long)
    #        $4 = option prefix(es) (single char for short, double for long)
    # Output: found_opts array populated, or RESULT set and returns 1
    local option="$1"
    local option_type="$2"
    local allowed="$3"
    local prefix="$4"

    if [[ "$option_type" == "short" ]]; then
        # Process short options: iterate through each character
        local j
        for ((j = 0; j < ${#option}; j++)); do
            local ch="${option:$j:1}"
            # Skip colons (option separators)
            if [[ "$ch" == ":" ]]; then
                continue
            fi
            # Check if this char is in allowed options (only if allowed specified).
            # Literal glob substring (quoted $ch), not =~ regex — otherwise an
            # option char like '.' would match any character in $allowed.
            if [[ -n "$allowed" && "$allowed" != *"$ch"* ]]; then
                RESULT="Invalid option: $prefix$ch"
                kk._return "$RESULT"
                return 1
            fi
            found_opts+=("$prefix$ch")
        done
    else
        # Process long option: single option validation.
        # Literal glob substring, not =~ regex, so an option name containing
        # a regex metacharacter is matched as itself.
        if [[ -n "$allowed" && "$allowed" != *" ${option} "* ]]; then
            RESULT="Invalid option: $prefix$option"
            kk._return "$RESULT"
            return 1
        fi
        found_opts+=("$prefix$option")
    fi
    RESULT=""
    kk._return "$RESULT"
    return 0
}

TCustomApplication._ParseLongOpts() {
    # Extract long options array from input
    # Input: $1 = should_fill_arrays flag, $2 = long_opts (string or ref name)
    # Output: long_opts_array populated
    local should_fill_arrays="$1"
    local long_opts="$2"

    long_opts_array=()

    if [[ "$should_fill_arrays" == "true" && "$long_opts" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && declare -p "$long_opts" &>/dev/null; then
        # Treat long_opts as array reference
        local -n long_ref="$long_opts"
        long_opts_array=("${long_ref[@]:-}")
    elif [[ -n "$long_opts" && ! "$long_opts" =~ ^- ]]; then
        # String of long options (space-separated)
        read -ra long_opts_array <<< "$long_opts"
    fi
}

TCustomApplication.CheckOptions() {
    local short_opts="$1"
    local long_opts="$2"
    local opts_param="${3:-}"
    local non_opts_param="${4:-}"
    local all_errors="${5:-false}"

    # Prepare arguments and common variables
    $this.call _PrepareArguments "$@"

    # Handle function overloading based on parameter count and types
    # If parameter 3 is "true" or "false", it is the all_errors parameter (3-param version)
    if [[ "$opts_param" == "true" || "$opts_param" == "false" ]]; then
        all_errors="$opts_param"
        opts_param=""
        non_opts_param=""
    fi

    # Check if output arrays should be filled
    local should_fill_arrays=false
    if [[ -n "$opts_param" && "$opts_param" != "true" && "$opts_param" != "false" ]]; then
        should_fill_arrays=true
    fi

    # Extract long options array
    local -a long_opts_array=()
    kk.call_silent "$this" _ParseLongOpts "$should_fill_arrays" "$long_opts"

    # OPTIMIZATION 2: Use pre-computed cached values
    local opt_char="${state[_OptionCharCache]:-$OptionChar}"
    local double_opt_char="${state[_DoubleOptionCharCache]:-$OptionChar$OptionChar}"
    local args_count="${state[_TCUSTAPP_ARGS_COUNT]:-0}"

    local error_msg=""
    local -a found_opts=()
    local -a found_non_opts=()

    # Validate short options - remove colons for validation
    local short_opts_clean="$short_opts"
    short_opts_clean="${short_opts_clean//:}"

    # OPTIMIZATION 3: Convert long_opts_array to validation string for faster lookups
    local long_opts_str=" ${long_opts_array[*]} "

    # Process each argument
    local i
    for ((i = 0; i < args_count; i++)); do
        local arg="${state[_TCUSTAPP_ARG_$i]}"

        # Check if this is a short option (single option char, not double, not just the char alone)
        if [[ "$arg" == "$opt_char"* && "$arg" != "$double_opt_char"* && "$arg" != "$opt_char" ]]; then
            local opts_str="${arg:${#opt_char}}"
            # Validate short options
            kk.call_silent "$this" _ValidateOption "$opts_str" "short" "$short_opts_clean" "$opt_char"
            if [[ $? -ne 0 ]]; then
                error_msg="$RESULT"
                break
            fi
        # Check if this is a long option (double option char)
        elif [[ "$arg" == "$double_opt_char"* && "$arg" != "$double_opt_char" ]]; then
            local long_opt="${arg:$((${#opt_char} * 2))}"
            # Validate long option
            kk.call_silent "$this" _ValidateOption "$long_opt" "long" "$long_opts_str" "$double_opt_char"
            if [[ $? -ne 0 ]]; then
                error_msg="$RESULT"
                break
            fi
        else
            # Non-option argument
            found_non_opts+=("$arg")
        fi
    done

    # Fill output arrays if provided
    if $should_fill_arrays; then
        # OPTIMIZATION 4: Use array references to avoid copying large arrays
        if [[ -n "$opts_param" ]]; then
            local -n opts_ref="$opts_param" 2>/dev/null
            opts_ref=("${found_opts[@]}")
        fi
        if [[ -n "$non_opts_param" ]]; then
            local -n non_opts_ref="$non_opts_param" 2>/dev/null
            non_opts_ref=("${found_non_opts[@]}")
        fi
    fi

    RESULT="$error_msg"
}

TCustomApplication.GetNonOptions() {
    local short_opts="$1"
    local long_opts="$2"
    local non_options_var="${3:-}"

    # Prepare arguments and common variables
    $this.call _PrepareArguments "$@"

    # Use CheckOptions to parse and extract non-options
    local -a non_opts=()
    kk.call_silent "$this" CheckOptions "$short_opts" "$long_opts" "_dummy_opts" "non_opts"

    # Store results if variable provided
    if [[ -n "$non_options_var" ]]; then
        declare -n non_opts_ref="$non_options_var" 2>/dev/null
        non_opts_ref=("${non_opts[@]}")
    fi

    RESULT="${#non_opts[@]}"
}

TCustomApplication.Terminate() {
    # Terminate with optional exit code parameter
    local exit_code="${1:-}"
    Terminated="true"

    if [[ -n "$exit_code" ]]; then
        export EXITCODE="$exit_code"
    fi
}

TCustomApplication.Run() {
    # Run loop until Terminated - check via property to support subshells
    while true; do
        local terminated_value="$($this.property Terminated)"
        if [[ "$terminated_value" == "true" ]]; then
            break
        fi
        sleep 0.01
    done
}

TCustomApplication.HandleException() {
    local sender="$1"
    local exception_msg="$2"

    # If OnException handler is set, call it - using function call instead of eval
    if [[ -n "$OnException" ]]; then
        # Call the handler function directly instead of eval
        "$OnException" "$sender" "$exception_msg"
    else
        # Otherwise call ShowException
        $this.call ShowException "$exception_msg"
    fi

    # If StopOnException is true, terminate the app
    if [[ "$StopOnException" == "true" ]]; then
        $this.call Terminate "$ExceptionExitCode"
    fi
}

TCustomApplication.ShowException() {
    local exception_msg="$1"
    # Default: echo the exception to stderr
    if [[ -n "$exception_msg" ]]; then
        echo "Exception: $exception_msg" >&2
    fi
    return 0
}

TCustomApplication.GetEnvironmentList() {
    local list_var="$1"
    local names_only="${2:-false}"

    # Get all environment variables
    if [[ "$names_only" == "true" ]]; then
        declare -n list_ref="$list_var" 2>/dev/null || return 0
        local i=0
        while IFS= read -r line; do
            local var_name="${line%%=*}"
            list_ref[$i]="$var_name"
            ((i++))
        done < <(env | sort)
    else
        declare -n list_ref="$list_var" 2>/dev/null || return 0
        local i=0
        while IFS= read -r line; do
            list_ref[$i]="$line"
            ((i++))
        done < <(env | sort)
    fi
}

TCustomApplication.Log() {
    local event_type="$1"
    local msg="$2"
    local arg1="${3:-}"
    local arg2="${4:-}"

    # Check if event type is in filter
    if [[ -n "$EventLogFilter" ]]; then
        if [[ "$EventLogFilter" != *"$event_type"* ]]; then
            return 0
        fi
    fi

    # Format and log message
    if [[ -n "$arg1" && "$arg1" != "false" ]]; then
        # Has format arguments
        echo "$event_type: $msg"
    else
        echo "$event_type: $msg"
    fi
}

TCustomApplication._getExeName() {
    # Return the executable name (parameter 0)
    RESULT="$0"
}

TCustomApplication.ConsoleApplication() {
    # Check if compiled as console application
    RESULT="true"
}

TCustomApplication.Location() {
    # Return directory of the application
    RESULT="$(kk.getScriptDir "${BASH_SOURCE[0]}")"
}

TCustomApplication.ParamCount() {
    # Return count of parameters
    RESULT="$#"
}

TCustomApplication.Params() {
    # Get parameter at index
    local index="$1"
    if [[ $index -ge 0 && $index -lt $# ]]; then
        RESULT="${!index}"
    else
        RESULT=""
    fi
}

TCustomApplication.EnvironmentVariable() {
    # Get environment variable value
    local var_name="$1"
    local var_value="${!var_name}"
    RESULT="$var_value"
}

build TCustomApplication
