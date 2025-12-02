#!/bin/bash

# Source kklass system (don't override SCRIPT_DIR)
TCUSTOMAPPLICATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TCUSTOMAPPLICATION_DIR/../../kklass/kklass.sh"
source "$TCUSTOMAPPLICATION_DIR/../../kkore/kuse.sh"

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
         # Initialize cache for getopts string conversion
         _CachedShortOpts=""
         _CachedGetoptOpts=""
         # Initialize cache flag for arguments initialization
         _ArgsInitialized="false"
         # Cache OptionChar for performance
         _CachedOptionChar="-"
         
         # Initialize arguments from script parameters if any provided
         if [[ $# -gt 0 ]]; then
             $this.SetArgs "$@"
         fi
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
    "property" "ExeName" "_getExeName" \
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
         
         # Initialize cache variables if not already done
         if [[ -z "$_CachedShortOpts" ]]; then
             _CachedShortOpts=""
             _CachedGetoptOpts=""
         fi
         
         # Handle -- separator: if first argument is --, skip it
         local start_index=1
         if [[ "$1" == "--" ]]; then
             start_index=2
         fi
         
         # Store each argument without shell escaping - use a safer approach
         for ((i = start_index; i <= $#; i++)); do
             # Get argument by position using indirect expansion
             local arg="${!i}"
             # Store arguments as-is, preserving their original form
             TCUSTAPP_ARGS+=("$arg")
         done
         
         # Mark arguments as initialized
         _ArgsInitialized="true"
     ' \
    \
    "procedure" "_EnsureArgsInitialized" '
         # Auto-initialize arguments from script parameters if not already done
         # This is called automatically from functions that need arguments
         if [[ "$_ArgsInitialized" == "false" ]]; then
             TCUSTAPP_ARGS=()
             for arg in "$@"; do
                 TCUSTAPP_ARGS+=("$arg")
             done
             _ArgsInitialized="true"
         fi
     ' \
    \
    "procedure" "_PrepareArguments" '
         # Internal helper: Initialize arguments and setup common variables
         # This consolidates the repetitive initialization logic
         $this.call _EnsureArgsInitialized "$@"
         
         # Pre-compute commonly used values to avoid redundant lookups
         OptionChar_Cache="$OptionChar"
         DoubleOptionChar_Cache="$OptionChar_Cache$OptionChar_Cache"
     ' \
    \
    "function" "_GetArgs" '
         # Get stored arguments array
         # Return count of arguments
         RESULT="${#TCUSTAPP_ARGS[@]}"
     ' \
    \
    "function" "_GetNextArgValue" '
         local -n args_array_ref="$1"
         local idx="$2"
         
         if [[ $((idx + 1)) -lt ${#args_array_ref[@]} ]]; then
             local next_arg="${args_array_ref[$((idx + 1))]}"
             if [[ ! "$next_arg" =~ ^- ]]; then
                 RESULT="$next_arg"
                 return 0
             fi
         fi
         
         RESULT=""
         return 1
     ' \
    \
    "function" "FindOptionIndex" '
         local short_opt="$1"
         local long_opt="${2:-}"
         local start_at="${3:--1}"
         
         # Prepare arguments and common variables
         $this.call _PrepareArguments "$@"
         
         # OPTIMIZATION 1: Use array reference instead of copying
         local -n args_ref=TCUSTAPP_ARGS
         
         # Get the current OptionChar
         local opt_char="$OptionChar_Cache"
         
         # Search for option in arguments starting from start_at
         local search_start=0
         [[ "$start_at" -ge 0 ]] && search_start="$start_at"
         
         local i
         for ((i = search_start; i < ${#args_ref[@]}; i++)); do
             local arg="${args_ref[$i]}"
             
             # Check short option (single char with option char prefix)
             if [[ -n "$short_opt" && "$arg" == "$opt_char$short_opt" ]]; then
                 RESULT="$i"
                 return 0
             fi
             
             # Check long option (with double option char prefix)
             if [[ -n "$long_opt" && "$arg" == "$opt_char$opt_char$long_opt" ]]; then
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
         
         # Prepare arguments and common variables
         $this.call _PrepareArguments "$@"
         
         # OPTIMIZATION 1: Use array reference instead of copying
         local -n args_ref=TCUSTAPP_ARGS
         
         # Find option using FindOptionIndex (checks both short and long options in one call)
         local idx
         $this.call FindOptionIndex "$opt" "$secondary_opt" -1
         idx="$RESULT"
         
         if [[ "$idx" -ge 0 ]]; then
             $this.call _GetNextArgValue args_ref "$idx"
             if [[ $? -eq 0 ]]; then
                 return 0
             fi
         fi
         
         RESULT=""
     ' \
    \
    "function" "GetOptionValues" '
         local short_opt="$1"
         local long_opt="${2:-}"
         
         # Prepare arguments and common variables
         $this.call _PrepareArguments "$@"
         
         # OPTIMIZATION 1: Use array reference instead of copying
         local -n args_ref=TCUSTAPP_ARGS
         
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
             
             $this.call _GetNextArgValue args_ref "$idx"
             if [[ $? -eq 0 ]]; then
                 values+=("$RESULT")
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
         
         # Prepare arguments and common variables
         $this.call _PrepareArguments "$@"
         
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
    "function" "_ValidateShortOptions" '
         # Validate and process short options from argument
         # Input: $1 = argument string (e.g. "abc"), $2 = allowed options string, $3 = opt_char
         # Output: found_opts array populated, or error_msg set and returns 1
         local opts_str="$1"
         local short_opts_clean="$2"
         local opt_char="$3"
         
         local j
         for ((j = 0; j < ${#opts_str}; j++)); do
             local ch="${opts_str:$j:1}"
             # Skip colons (option separators)
             if [[ "$ch" == ":" ]]; then
                 continue
             fi
             # Check if this char is in short_opts_clean (only if short_opts specified)
             if [[ -n "$short_opts_clean" && ! "$short_opts_clean" =~ $ch ]]; then
                 RESULT="Invalid option: $opt_char$ch"
                 return 1
             fi
             found_opts+=("$opt_char$ch")
         done
         return 0
     ' \
    \
    "function" "_ValidateLongOptions" '
         # Validate and process long option
         # Input: $1 = long option name, $2 = allowed options string, $3 = double_opt_char
         # Output: found_opts array populated, or RESULT set and returns 1
         local long_opt="$1"
         local long_opts_str="$2"
         local double_opt_char="$3"
         
         # Check if long_opts_str is not empty (if empty, accepts any long option)
         if [[ -n "$long_opts_str" ]]; then
             if [[ ! "$long_opts_str" =~ " ${long_opt} " ]]; then
                 RESULT="Invalid option: $double_opt_char$long_opt"
                 return 1
             fi
         fi
         found_opts+=("$double_opt_char$long_opt")
         return 0
     ' \
    \
    "function" "_ParseLongOpts" '
         # Extract long options array from input
         # Input: $1 = should_fill_arrays flag, $2 = long_opts (string or ref name)
         # Output: long_opts_array populated
         local should_fill_arrays="$1"
         local long_opts="$2"
         
         long_opts_array=()
         
         if [[ "$should_fill_arrays" == "true" ]]; then
             # Treat long_opts as array reference
             local -n long_ref="$long_opts" 2>/dev/null
             long_opts_array=("${long_ref[@]:-}")
         elif [[ -n "$long_opts" && ! "$long_opts" =~ ^- ]]; then
             # String of long options (space-separated)
             read -ra long_opts_array <<< "$long_opts"
         fi
     ' \
    \
    "function" "CheckOptions" '
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
         $this.call _ParseLongOpts "$should_fill_arrays" "$long_opts"
         
         # OPTIMIZATION 1: Use array reference instead of copying
         local -n args_ref=TCUSTAPP_ARGS
         
         # OPTIMIZATION 2: Use pre-computed cached values
         local opt_char="$OptionChar_Cache"
         local double_opt_char="$DoubleOptionChar_Cache"
         
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
         for ((i = 0; i < ${#args_ref[@]}; i++)); do
             local arg="${args_ref[$i]}"
             
             # Check if this is a short option (single option char, not double, not just the char alone)
             if [[ "$arg" == "$opt_char"* && "$arg" != "$double_opt_char"* && "$arg" != "$opt_char" ]]; then
                 local opts_str="${arg:${#opt_char}}"
                 # Validate short options
                 $this.call _ValidateShortOptions "$opts_str" "$short_opts_clean" "$opt_char"
                 if [[ $? -ne 0 ]]; then
                     error_msg="$RESULT"
                     break
                 fi
             # Check if this is a long option (double option char)
             elif [[ "$arg" == "$double_opt_char"* && "$arg" != "$double_opt_char" ]]; then
                 local long_opt="${arg:$((${#opt_char} * 2))}"
                 # Validate long option
                 $this.call _ValidateLongOptions "$long_opt" "$long_opts_str" "$double_opt_char"
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
             local -n opts_ref="$opts_param" 2>/dev/null
             opts_ref=("${found_opts[@]}")
             local -n non_opts_ref="$non_opts_param" 2>/dev/null
             non_opts_ref=("${found_non_opts[@]}")
         fi
         
         RESULT="$error_msg"
     ' \
    \
    "function" "GetNonOptions" '
         local short_opts="$1"
         local long_opts="$2"
         local non_options_var="${3:-}"
         
         # Prepare arguments and common variables
         $this.call _PrepareArguments "$@"
         
         # Use CheckOptions to parse and extract non-options
         local -a non_opts=()
         $this.call CheckOptions "$short_opts" "$long_opts" "_dummy_opts" "non_opts"
         
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
    "function" "_getExeName" '
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
         RESULT="$(kk.getScriptDir "${BASH_SOURCE[0]}")"
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
     '
