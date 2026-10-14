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

# R8 of the U4 final review: the platform constants come from $OSTYPE (no
# `$(uname -s)` fork at load) and keep the values the uname spelling gave:
# loaded with an EMPTY PATH (uname unreachable) after kbool + kklass_pascal,
# tpath still sees this platform (the reference: uname -s, here, with PATH).
case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*) WANT_OS='w=1 ps=; alt=\ vol=:' ;;
    *)                    WANT_OS='w=0 ps=: alt=/ vol=/' ;;
esac
cat > "$KCLT_TMP/os.sh" <<'EOF'
source "$KBOOL_ROOT/kbool.sh" || exit 9
kk.uses kklass_pascal || exit 8
PATH=""
kk.uses tpath || exit 7
echo "w=$__TPATH_IS_WINDOWS ps=$__TPATH_PATH_SEPARATOR alt=$__TPATH_ALT_DIRECTORY_SEPARATOR_CHAR vol=$__TPATH_VOLUME_SEPARATOR_CHAR"
EOF
kclt_run "$KCLT_TMP/neutral" "$KCLT_TMP/os.sh"
kclt_expect "tpath: the platform constants without a fork — loaded under an empty PATH they still match uname -s ($WANT_OS) [U4 final review R8]" "$WANT_OS"
