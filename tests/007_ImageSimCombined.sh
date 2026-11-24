#!/usr/bin/env bash
# ImageSimCombined — the simulated image start (kklass/docs/dev/IMAGE_PLAN.md
# §5.2; kcl/tests/image_sim.sh) of COMBINED loads, where one unit's hook
# appends to a registry another unit's hook declares (the H1 case, image
# stage I1b): tutil tawk tfind tsed in two orders and tpipe tutil, each under
# no locale and LANG=C.UTF-8; the four with caller presets of the registries
# (an array kept, a scalar replaced); and ONE load of kklass and every kcl
# unit. Then a normal load of the wrapper family + tfile under presets and
# locales: the public VARs the I1b hooks set (TUTIL_OUT_PREFIXES /
# _SUFFIXES, TFILE_USE_CP, LC_CTYPE) keep a caller's array preset, replace a
# scalar one, take their defaults when unset, and LC_CTYPE is exported only
# when no locale variable is set (the move into the hooks changed no
# behaviour).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ktests/ktest.sh"
kt_test_init "ImageSimCombined" "$SCRIPT_DIR" "$@"
source "$SCRIPT_DIR/kcl_units.sh"
kclt_setup
kclt_simscript

for loc in "" LANG=C.UTF-8; do
    for set in "tutil tawk tfind tsed" "tsed tfind tawk tutil" "tpipe tutil"; do
        read -r -a us <<<"$set"
        kclt_simrun ${loc:+"$loc"} -- "$KCLT_TMP/sim.sh" "${us[@]}"
        kclt_expect "kk.uses $set together, ${loc:-no locale variable}: the simulated image start equals the end-of-load state (each wrapper's hook appends to tutil's registries again, once) [IMAGE_PLAN §5.2 H1, I1b]" "sim:ok"
    done
done

for pre in "declare -ga TUTIL_OUT_PREFIXES=(__mine_) TUTIL_OUT_SUFFIXES=(_mine)" "TUTIL_OUT_PREFIXES=scalar TUTIL_OUT_SUFFIXES=scalar"; do
    KCLT_SIM_PRE=$pre
    kclt_simrun -- "$KCLT_TMP/sim.sh" tutil tawk tfind tsed
    KCLT_SIM_PRE=""
    kclt_expect "kk.uses tutil tawk tfind tsed after '$pre': the simulated image start (the presets put back first) equals the end-of-load state [IMAGE_PLAN §5.2 H1, I1b]" "sim:ok"
done

kclt_simrun -- "$KCLT_TMP/sim.sh" kklass "${KCLT_SIM_REST[@]}" "${KCLT_SIM_FV[@]}"
kclt_expect "kklass and all $(( ${#KCLT_SIM_REST[@]} + ${#KCLT_SIM_FV[@]} )) kcl units in ONE kk.uses: the simulated image start equals the end-of-load state; every hook VAR listed [IMAGE_PLAN §5.2, I1b]" "sim:ok"

# --- a normal load: presets and defaults of the I1b hook VARs ---------------
cat > "$KCLT_TMP/pub.sh" <<'EOF'
source "$KBOOL_ROOT/kbool.sh" || exit 2
if [[ -n ${KCLT_SIM_PRE-} ]]; then eval "$KCLT_SIM_PRE"; fi
kk.uses tsed tutil tawk tfind tfile || exit 3
printf '%s|%s|%s|%s|%s\n' "${TUTIL_OUT_PREFIXES[*]}" "${TUTIL_OUT_SUFFIXES[*]}" "$TFILE_USE_CP${TFILE_USE_CP@a}" \
    "${LC_CTYPE-<unset>}" "${LC_CTYPE@a}"
EOF
P0="__tu_ __tg_ __th_ __tt_ __tsd_ __taw_ __tfd_"
S0="_exprs _rfrom _rto _rflags _progs _vnames _vvals"
kclt_simrun -- "$KCLT_TMP/pub.sh"
kclt_expect "a normal load (tsed tutil tawk tfind tfile), no locale variable: the registries hold tutil's defaults then each wrapper's entries in load order, TFILE_USE_CP true (not readonly), LC_CTYPE=C.UTF-8 exported [I1b]" \
    "$P0|_args _argv _paths $S0|true|C.UTF-8|x"
KCLT_SIM_PRE="declare -ga TUTIL_OUT_PREFIXES=(__mine_) TUTIL_OUT_SUFFIXES=(_mine); TFILE_USE_CP=stale"
kclt_simrun LANG=C.UTF-8 -- "$KCLT_TMP/pub.sh"
KCLT_SIM_PRE=""
kclt_expect "a normal load under LANG=C.UTF-8 with array presets of both registries and TFILE_USE_CP=stale: the arrays kept (no tutil default) plus each wrapper's entries, TFILE_USE_CP recomputed, LC_CTYPE not set [I1b]" \
    "__mine_ __tsd_ __taw_ __tfd_|_mine $S0|true|<unset>|"
KCLT_SIM_PRE="TUTIL_OUT_PREFIXES=scalar TUTIL_OUT_SUFFIXES=scalar; readonly TFILE_USE_CP=false"
kclt_simrun LC_ALL=C -- "$KCLT_TMP/pub.sh"
KCLT_SIM_PRE=""
kclt_expect "a normal load under LC_ALL=C with scalar presets of both registries and a readonly TFILE_USE_CP=false: the scalars replaced by the defaults plus each wrapper's entries, the readonly value kept, LC_CTYPE not set [I1b]" \
    "$P0|_args _argv _paths $S0|falser|<unset>|"
