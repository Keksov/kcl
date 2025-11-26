#!/bin/bash
# helper_external_app.sh - Helper application for testing SetArgs with external arguments
# This simulates an external program that receives arguments and then calls SetArgs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TCUSTOMAPPLICATION_DIR="$SCRIPT_DIR/.."
source "$TCUSTOMAPPLICATION_DIR/tcustomapplication.sh"

# Create application instance
TCustomApplication.new app

# Original arguments passed to this script
original_args=("$@")

# Test 1: Store original arguments and check them
app.SetArgs "${original_args[@]}"

# Get the index of first argument
if [[ ${#original_args[@]} -gt 0 ]]; then
    app.FindOptionIndex "o" "" 0
    option_index=$RESULT
    
    # Check if old arguments are present (they shouldn't be, only new ones)
    app.FindOptionIndex "x" "" 0
    old_option_index=$RESULT
    
    # Return results
    echo "original_count=${#original_args[@]}"
    echo "new_option_index=$option_index"
    echo "old_option_index=$old_option_index"
else
    echo "no_arguments"
fi

# Test 2: Replace arguments with new ones
app.SetArgs -o output.txt --verbose file.txt

# Get information about new arguments
app.FindOptionIndex "o" "" 0
new_option_index=$RESULT
app.GetOptionValue "o" ""
output_value=$RESULT
app.HasOption "" "verbose"
has_verbose=$RESULT

echo "new_args_set=true"
echo "new_option_index=$new_option_index"
echo "output_value=$output_value"
echo "has_verbose=$has_verbose"

app.delete
