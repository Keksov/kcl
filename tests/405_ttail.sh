#!/bin/bash
# The runtime checks of ONE migrated kcl unit — the stem after `NNN_` names it;
# the checks are kclt_unit_tests in kcl_units.sh (one file per unit: loads run
# in parallel under the threaded runner).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
UNIT_NAME=${BASH_SOURCE[0]##*/}; UNIT_NAME=${UNIT_NAME#[0-9][0-9][0-9]_}; UNIT_NAME=${UNIT_NAME%.sh}
kt_test_init "Unit_$UNIT_NAME" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
kclt_setup
kclt_unit_tests "$UNIT_NAME"
