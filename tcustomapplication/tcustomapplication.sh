#!/bin/bash

# Source kklass system (don't override SCRIPT_DIR)
TCUSTOMAPPLICATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TCUSTOMAPPLICATION_DIR/../../kklass/kklass.sh"

# Define TCustomApplication class
defineClass "TCustomApplication" "" \
    "constructor" '
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
        TCUSTAPP_ARGS=()
    ' \
    \
    "property" "Terminated" \
    "property" "Title" \
    "property" "HelpFile" \
    "property" "OptionChar" \
    "property" "CaseSensitiveOptions" \
    "property" "StopOnException" \
    "property" "ExceptionExitCode" \
    "property" "OnException" \
    "property" "EventLogFilter" \
    \
    "procedure" "Initialize" '
        # Initialize sets Terminated to false
        Terminated="false"
    ' \
    \
    "procedure" "SetArgs" '
        # Store command-line arguments for this instance in the instance data
        # Clear existing arguments first
        TCUSTAPP_ARGS=()
        
        # Handle -- separator: if first argument is --, skip it
        local start_index=0
        if [[ "$1" == "--" ]]; then
            start_index=1
        fi
        
        # Store each argument with proper escaping for later retrieval
        for ((i = start_index + 1; i <= $#; i++)); do
            # Get argument by position using indirect expansion
            local arg="${!i}"
            # Use printf %q for proper shell escaping
            TCUSTAPP_ARGS+=("$(printf %q "$arg")")
        done
    ' \
    \
    "function" "_GetArgs" '
        # Get stored arguments array
        # Return count of arguments
        RESULT="${#TCUSTAPP_ARGS[@]}"
    ' \
    \
    "function" "FindOptionIndex" '
        local short_opt="$1"
        local long_opt="${2:-}"
        local start_at="${3:--1}"
        
        # Get arguments array
        local -a args_array=()
        for arg in "${TCUSTAPP_ARGS[@]}"; do
            # Evaluate the escaped argument back to original form
            eval "args_array+=(\"$arg\")"
        done
        
        # Search for option in arguments starting from start_at
        local search_start=0
        [[ "$start_at" -ge 0 ]] && search_start="$start_at"
        
        local i
        for ((i = search_start; i < ${#args_array[@]}; i++)); do
            local arg="${args_array[$i]}"
            
            # Check short option (single char with dash)
            if [[ -n "$short_opt" && "$arg" == "-$short_opt" ]]; then
                RESULT="$i"
                return 0
            fi
            
            # Check long option (with double dash)
            if [[ -n "$long_opt" && "$arg" == "--$long_opt" ]]; then
                RESULT="$i"
                return 0
            fi
        done
        
        RESULT="-1"
    ' \
    \
    "function" "GetOptionValue" '
        local opt="$1"
        local secondary_opt="${2:-}"
        
        # Get arguments array
        local -a args_array=()
        for arg in "${TCUSTAPP_ARGS[@]}"; do
            # Evaluate the escaped argument back to original form
            eval "args_array+=(\"$arg\")"
        done
        
        # Try short option first
        if [[ -n "$opt" ]]; then
            local idx
            $this.call FindOptionIndex "$opt" "" -1
            idx="$RESULT"
            
            if [[ "$idx" -ge 0 && $((idx + 1)) -lt ${#args_array[@]} ]]; then
                local next_arg="${args_array[$((idx + 1))]}"
                # Check if next arg is not an option
                if [[ ! "$next_arg" =~ ^- ]]; then
                    RESULT="$next_arg"
                    return 0
                fi
            fi
        fi
        
        # Try secondary/long option
        if [[ -n "$secondary_opt" ]]; then
            local idx
            $this.call FindOptionIndex "" "$secondary_opt" -1
            idx="$RESULT"
            
            if [[ "$idx" -ge 0 && $((idx + 1)) -lt ${#args_array[@]} ]]; then
                local next_arg="${args_array[$((idx + 1))]}"
                # Check if next arg is not an option
                if [[ ! "$next_arg" =~ ^- ]]; then
                    RESULT="$next_arg"
                    return 0
                fi
            fi
        fi
        
        RESULT=""
    ' \
    \
    "function" "GetOptionValues" '
        local short_opt="$1"
        local long_opt="${2:-}"
        
        # Get arguments array
        local -a args_array=()
        for arg in "${TCUSTAPP_ARGS[@]}"; do
            # Evaluate the escaped argument back to original form
            eval "args_array+=(\"$arg\")"
        done
        
        local -a values=()
        
        # Collect all values for this option
        local i=0
        while true; do
            local idx
            $this.call FindOptionIndex "$short_opt" "$long_opt" "$i"
            idx="$RESULT"
            
            if [[ "$idx" -lt 0 ]]; then
                break
            fi
            
            if [[ $((idx + 1)) -lt ${#args_array[@]} ]]; then
                local next_arg="${args_array[$((idx + 1))]}"
                if [[ ! "$next_arg" =~ ^- ]]; then
                    values+=("$next_arg")
                fi
            fi
            
            i=$((idx + 1))
        done
        
        # Return array count and values
        if [[ ${#values[@]} -gt 0 ]]; then
            RESULT="${#values[@]}:${values[*]}"
        else
            RESULT="0:"
        fi
    ' \
    \
    "function" "HasOption" '
        local opt="$1"
        local secondary_opt="${2:-}"
        
        local idx
        $this.call FindOptionIndex "$opt" "$secondary_opt" -1
        idx="$RESULT"
        
        if [[ "$idx" -ge 0 ]]; then
            RESULT="true"
        else
            RESULT="false"
        fi
    ' \
    \
    "function" "CheckOptions" '
        local short_opts="$1"
        local long_opts="$2"
        local opts_param="${3:-}"
        local non_opts_param="${4:-}"
        
        # Get arguments array
        local -a args_array=()
        for arg in "${TCUSTAPP_ARGS[@]}"; do
            # Evaluate the escaped argument back to original form
            eval "args_array+=(\"$arg\")"
        done
        
        # Build getopt options string
        local getopt_opts=""
        for ((i = 0; i < ${#short_opts}; i++)); do
            local ch="${short_opts:$i:1}"
            if [[ "$ch" != ":" ]]; then
                getopt_opts="$getopt_opts$ch"
                if [[ $((i + 1)) -lt ${#short_opts} && "${short_opts:$((i+1)):1}" == ":" ]]; then
                    getopt_opts="$getopt_opts:"
                    ((i++))
                fi
            fi
        done
        
        # Use getopt to validate
        local long_opts_str=""
        if [[ -n "$long_opts" ]]; then
            long_opts_str="$(echo "$long_opts" | sed "s/ /,/g")"
        fi
        
        local getopts_output
        if [[ -n "$long_opts_str" ]]; then
            getopts_output=$(getopt -o "$getopt_opts" --long "$long_opts_str" -- "${args_array[@]}" 2>&1)
        else
            getopts_output=$(getopt -o "$getopt_opts" -- "${args_array[@]}" 2>&1)
        fi
        
        if [[ $? -eq 0 ]]; then
            RESULT=""
        else
            RESULT="$getopts_output"
        fi
    ' \
    \
    "function" "GetNonOptions" '
        local short_opts="$1"
        local long_opts="$2"
        local non_options_var="${3:-}"
        
        # Get arguments array
        local -a args_array=()
        for arg in "${TCUSTAPP_ARGS[@]}"; do
            # Evaluate the escaped argument back to original form
            eval "args_array+=(\"$arg\")"
        done
        
        # Build getopt options string
        local getopt_opts=""
        for ((i = 0; i < ${#short_opts}; i++)); do
            local ch="${short_opts:$i:1}"
            if [[ "$ch" != ":" ]]; then
                getopt_opts="$getopt_opts$ch"
                if [[ $((i + 1)) -lt ${#short_opts} && "${short_opts:$((i+1)):1}" == ":" ]]; then
                    getopt_opts="$getopt_opts:"
                    ((i++))
                fi
            fi
        done
        
        # Use getopt to parse
        local long_opts_str=""
        if [[ -n "$long_opts" ]]; then
            long_opts_str="$(echo "$long_opts" | sed "s/ /,/g")"
        fi
        
        local -a non_opts=()
        local getopts_output
        if [[ -n "$long_opts_str" ]]; then
            getopts_output=$(getopt -o "$getopt_opts" --long "$long_opts_str" -- "${args_array[@]}" 2>&1)
        else
            getopts_output=$(getopt -o "$getopt_opts" -- "${args_array[@]}" 2>&1)
        fi
        
        if [[ $? -eq 0 ]]; then
            # Parse output to get non-options after --
            local found_sep=0
            while IFS= read -r line; do
                if [[ "$line" == "--" ]]; then
                    found_sep=1
                elif [[ "$found_sep" -eq 1 ]]; then
                    non_opts+=("$line")
                fi
            done <<< "$getopts_output"
        fi
        
        # Store results if variable provided
        if [[ -n "$non_options_var" ]]; then
            declare -n non_opts_ref="$non_options_var" 2>/dev/null
            non_opts_ref=("${non_opts[@]}")
        fi
        
        RESULT="${#non_opts[@]}"
    ' \
    \
    "procedure" "Terminate" '
        # Terminate with optional exit code parameter
        local exit_code="${1:-}"
        Terminated="true"
        
        if [[ -n "$exit_code" ]]; then
            export EXITCODE="$exit_code"
        fi
    ' \
    \
    "procedure" "Run" '
        # Run loop until Terminated - check via property to support subshells
        while true; do
            local terminated_value="$($this.property Terminated)"
            if [[ "$terminated_value" == "true" ]]; then
                break
            fi
            sleep 0.01
        done
    ' \
    \
    "procedure" "HandleException" '
        local sender="$1"
        local exception_msg="$2"
        
        # If OnException handler is set, call it
        if [[ -n "$OnException" ]]; then
            eval "$OnException \"$sender\" \"$exception_msg\""
        else
            # Otherwise call ShowException
            $this.call ShowException "$exception_msg"
        fi
        
        # If StopOnException is true, terminate the app  
        if [[ "$StopOnException" == "true" ]]; then
            $this.call Terminate "$ExceptionExitCode"
        fi
    ' \
    \
    "procedure" "ShowException" '
        local exception_msg="$1"
        # Default: echo the exception to stderr
        [[ -n "$exception_msg" ]] && echo "Exception: $exception_msg" >&2
    ' \
    \
    "procedure" "GetEnvironmentList" '
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
    ' \
    \
    "procedure" "Log" '
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
    ' \
    \
    "function" "exeName" '
        # Return the executable name (parameter 0)
        RESULT="$0"
    ' \
    \
    "function" "ConsoleApplication" '
        # Check if compiled as console application
        RESULT="true"
    ' \
    \
    "function" "Location" '
        # Return directory of the application
        local script_dir="$(dirname "$0")"
        [[ ! "$script_dir" = /* ]] && script_dir="$(cd "$script_dir" 2>/dev/null && pwd)"
        RESULT="$script_dir"
    ' \
    \
    "function" "ParamCount" '
        # Return count of parameters
        RESULT="$#"
    ' \
    \
    "function" "Params" '
        # Get parameter at index
        local index="$1"
        if [[ $index -ge 0 && $index -lt $# ]]; then
            RESULT="${!index}"
        else
            RESULT=""
        fi
    ' \
    \
    "function" "EnvironmentVariable" '
        # Get environment variable value
        local var_name="$1"
        local var_value="${!var_name}"
        RESULT="$var_value"
    ' \
    \
    "function" "title" '
        # Getter for Title property (lowercase alias)
        # Check if lowercase property was set via .property title =
        local lowercase_title="$($this.property title)"
        if [[ -n "$lowercase_title" ]]; then
            RESULT="$lowercase_title"
        else
            RESULT="$Title"
        fi
    ' \
    \
    "function" "terminated" '
        # Getter for Terminated property (lowercase alias)
        RESULT="$Terminated"
    ' \
    \
    "function" "helpfile" '
        # Getter for HelpFile property (lowercase alias)
        RESULT="$HelpFile"
    ' \
    \
    "function" "optionchar" '
        # Getter for OptionChar property (lowercase alias)
        RESULT="$OptionChar"
    ' \
    \
    "function" "casesensitiveoptions" '
        # Getter for CaseSensitiveOptions property (lowercase alias)
        RESULT="$CaseSensitiveOptions"
    ' \
    \
    "function" "stoponexception" '
        # Getter for StopOnException property (lowercase alias)
        RESULT="$StopOnException"
    ' \
    \
    "function" "exceptionexitcode" '
        # Getter for ExceptionExitCode property (lowercase alias)
        RESULT="$ExceptionExitCode"
    ' \
    \
    "function" "onexception" '
        # Getter for OnException property (lowercase alias)
        RESULT="$OnException"
    ' \
    \
    "function" "eventlogfilter" '
        # Getter for EventLogFilter property (lowercase alias)
        RESULT="$EventLogFilter"
    '