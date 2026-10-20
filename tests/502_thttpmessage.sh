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
kclt_unit_tests "$UNIT_NAME"

# U44 (owner 2026-10-14, critic_u4 C5): a declared namespace is shared only
# within its owner's folder (thttprouter / thttpserver share ths with
# thttpmessage — their own once/name checks); a user unit in another folder
# declaring ths / tca / TSet / kk / tpath (a unit name, also a class) — or a
# unit NAMED ths — is refused and defines nothing.
mkdir -p "$KCLT_TMP/user"
for n in ths tca TSet kk tpath; do
    printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2' \
        "kk.unit u_$n || return \$__kk_unit_rc" "kk.namespace $n || return" "$n.hijack() { echo HIJACK; }" > "$KCLT_TMP/user/u_$n.sh"
done
printf '%s\n' '[[ ${__KK_UNITS[@]@a} == A* ]] || source "${KBOOL_HOME-}/kbool.sh" || return 2' \
    'kk.unit ths || return $__kk_unit_rc' 'ths.hijack() { echo HIJACK; }' > "$KCLT_TMP/user/ths.sh"
cat > "$KCLT_TMP/u44.sh" <<'EOF'
source "$KBOOL_ROOT/kbool.sh" || exit 9
kk.uses thttpmessage tcustomapplication thashset tpath || exit 8
o=""
for n in ths tca TSet kk tpath; do
    v=${__KK_NAMESPACES[$n]-}
    source "$KCLT_TMP/user/u_$n.sh" 2>>"$KCLT_TMP/u44.err"; r=$?
    w=${__KK_NAMESPACES[$n]-}
    [[ $v == "$w" ]] && w=same || w=changed
    o+="$n=$r,$w,$(declare -F $n.hijack || echo none) "
done
source "$KCLT_TMP/user/ths.sh" 2>>"$KCLT_TMP/u44.err"; o+="unit-ths=$?,$(declare -F ths.hijack || echo none)"
echo "$o"
EOF
rm -f "$KCLT_TMP/u44.err"
kclt_run "$KCLT_TMP/neutral" "$KCLT_TMP/u44.sh"
E=""; [[ -f $KCLT_TMP/u44.err ]] && E="$(<"$KCLT_TMP/u44.err")"
[[ $E == *"kk.namespace ths: 'ths' is already the function namespace of unit thttpmessage ("*"/kcl/thttpserver/thttpmessage.sh); only a file in that folder may share it (U44)"* ]] && E=msg-ok
OUT+=" $E"
kclt_expect "U44: a user unit outside the owner's folder declaring ths / tca / TSet / kk / tpath, or a unit named ths, is refused (rc 2; the namespace keeps its owner, no X.hijack defined) [U44, critic_u4 C5]" \
    "ths=2,same,none tca=2,same,none TSet=2,same,none kk=2,same,none tpath=2,same,none unit-ths=2,none msg-ok"
