#!/usr/bin/env bash
# The runtime checks of ONE migrated kcl unit — the stem after `NNN_` names it;
# the checks are kclt_unit_tests in kcl_units.sh (one file per unit: loads run
# in parallel under the threaded runner).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
UNIT_NAME=${BASH_SOURCE[0]##*/}; UNIT_NAME=${UNIT_NAME#[0-9][0-9][0-9]_}; UNIT_NAME=${UNIT_NAME%.sh}
kt_test_init "Unit_$UNIT_NAME" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
kclt_setup

# tutil only: its two out-name registries (TUTIL_OUT_PREFIXES / _SUFFIXES) are
# process state every descendant extends at ITS load (tfind `__tfd_`, tsed
# `_exprs`, ...). Across the U24' dev hatch — `kk.unit --forget tutil` + a
# re-source, checked inside the once process (hooks of kclt_unit_tests, no
# extra load) — an entry a descendant appended must stay: a reload that
# re-declared them would silently drop it, and the descendant's scratch prefix
# would become a fillable output name again [G4, pattern rule 10 / amendment l].
rm -f "$KCLT_TMP/registry.out"
KCLT_FORGET_PRE='TUTIL_OUT_PREFIXES+=( __kclt_ ); TUTIL_OUT_SUFFIXES+=( _kclt )'
KCLT_FORGET_POST='
if tutil._badOut __kclt_x; then KT_r=refused; else KT_r=accepted; fi
echo "prefixes=${TUTIL_OUT_PREFIXES[*]} suffixes=${TUTIL_OUT_SUFFIXES[*]} __kclt_x=$KT_r" > "$KCLT_TMP/registry.out"'
kclt_unit_tests "$UNIT_NAME"

kt_test_start "tutil registries: an entry appended before kk.unit --forget tutil + a re-source (under set -eu) is still there after it, and its prefix is still refused [U24', G4, amendment l]"
want="prefixes=__tu_ __tg_ __th_ __tt_ __kclt_ suffixes=_args _argv _paths _kclt __kclt_x=refused"
OUT=""; [[ -f $KCLT_TMP/registry.out ]] && OUT="$(<"$KCLT_TMP/registry.out")"
if [[ $OUT == "$want" ]]; then
    kt_test_pass "ok"
else
    kt_test_fail "out='$OUT' want='$want' (stderr: see the once test)"
fi
