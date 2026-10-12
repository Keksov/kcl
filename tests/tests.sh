#!/bin/bash
# Test runner for the kcl-level tests (unit headers of the kcl units) using ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/../../ktests/ktests.sh" "$SCRIPT_DIR" "kcl Units Test Suite" "$@"
