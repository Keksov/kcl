#!/usr/bin/env bash
# Test runner for fv.views tests using ktests framework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../../../ktests/ktests.sh" "$SCRIPT_DIR" "fv.views Test Suite" "$@"
