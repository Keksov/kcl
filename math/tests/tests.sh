#!/bin/bash
# Test runner for math tests using ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/../../../ktests/ktests.sh" "$SCRIPT_DIR" "Math Test Suite" "$@"
