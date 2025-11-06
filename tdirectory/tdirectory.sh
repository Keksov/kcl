#!/bin/bash

# Source kklass system (don't override SCRIPT_DIR)
TDIRECTORY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TDIRECTORY_DIR/../../kklass/kklass.sh"




# Define the tdirectory class 
defineClass "tdirectory" ""

#echo "tdirectory class created successfully"
