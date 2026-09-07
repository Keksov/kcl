#!/bin/bash
# helper_external_app.sh - Helper application for testing SetArgs with external
# arguments. It simulates a real program: it receives a command line and hands
# it to the application itself with `SetArgs "$@"` (nothing is auto-captured any
# more — finding TCA-04).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TCUSTOMAPPLICATION_DIR="${TCUSTOMAPPLICATION_DIR:-$SCRIPT_DIR/..}"
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

TCustomApplication.new app

# Original arguments passed to this script
original_args=("$@")
app.SetArgs "${original_args[@]}"
printf 'original_count=%s\n' "${#original_args[@]}"

# Replace the arguments with new ones
app.SetArgs -o output.txt --verbose file.txt

app.FindOptionIndex "o" ""
new_option_index=$RESULT
app.GetOptionValue "o" ""
output_value=$RESULT
app.HasOption "" "verbose" || :
has_verbose=$RESULT

printf 'new_option_index=%s\n' "$new_option_index"
printf 'output_value=%s\n' "$output_value"
printf 'has_verbose=%s\n' "$has_verbose"

app.delete
