#!/usr/bin/env bash
# Test runner for fv.mouse tests using ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../../../ktests/ktests.sh" "$SCRIPT_DIR" "fv.mouse Test Suite" "$@"
