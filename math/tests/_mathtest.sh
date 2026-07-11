#!/bin/bash
# Shared helper for the math test suite: pulls in the ktest framework and adds
# kt_assert_near — the tolerance comparison used for Tier-B (float-engine)
# results, which match FPC Double only to ~1-2 ulps.
#
# This is NOT a test file: the runner's "/[0-9][0-9][0-9]_" filter skips it
# (no NNN_ prefix), so it is never executed on its own.

_MT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_MT_DIR/../../../ktests/ktest.sh"

# kt_assert_near EXPECTED ACTUAL [RELTOL=1e-12]
#   Succeeds (returns 0) when |EXPECTED - ACTUAL| <= RELTOL * max(1, |EXPECTED|),
#   i.e. relative tolerance, degrading to absolute tolerance for values near 0.
#   Uses awk (a fork) — perfectly fine in test scaffolding.
kt_assert_near() {
    local e=$1 a=$2 tol=${3:-1e-12}
    awk -v e="$e" -v a="$a" -v t="$tol" 'BEGIN{
        d = e - a; if (d < 0) d = -d
        m = (e < 0 ? -e : e); if (m < 1) m = 1
        exit !(d <= t * m)
    }'
}
