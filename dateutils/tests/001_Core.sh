#!/bin/bash
# Core representation (P0): civil calendar, KDT split/join, ISO format/parse,
# wall clock, dateOf/timeOf, constant getters, and the perf/shape contracts.
#
# NOTE on FPC parity: none of tw16040's functions land in P0 (they are
# EncodeDateTime/YearOf/Julian/scanDateTime = P1+). Every check here is
# therefore "new coverage" and has a row in ../TEST_COVERAGE_NOTES.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "Core" "$SCRIPT_DIR" "$@"

DATEUTILS_DIR="$SCRIPT_DIR/.."
[[ -f "$DATEUTILS_DIR/dateutils.sh" ]] && source "$DATEUTILS_DIR/dateutils.sh"

# ---------------------------------------------------------------------------
# 1. Civil calendar + KDT join/split roundtrip over a sampled grid
# ---------------------------------------------------------------------------
kt_test_start "KDT join/split roundtrip over the sampled grid (incl. leap/pre-1970)"
years=(1899 1900 1970 1999 2000 2004 2100 2400)
months=(1 2 3 4 6 9 12)
days=(1 15 28)
times=("0 0 0 0" "23 59 59 999" "12 30 45 123")
grid_fail=""
grid_count=0
for y in "${years[@]}"; do
    for mo in "${months[@]}"; do
        for d in "${days[@]}"; do
            for t in "${times[@]}"; do
                read -r h mi s ms <<< "$t"
                dateutils._join_kdt "$y" "$mo" "$d" "$h" "$mi" "$s" "$ms"
                kdt="$REPLY"
                unset __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
                dateutils._split_kdt "$kdt"
                grid_count=$((grid_count + 1))
                if [[ "$__kdt_y $__kdt_mo $__kdt_d $__kdt_h $__kdt_mi $__kdt_s $__kdt_ms" \
                      != "$y $mo $d $h $mi $s $ms" ]]; then
                    grid_fail="$y-$mo-$d $h:$mi:$s.$ms -> got $__kdt_y-$__kdt_mo-$__kdt_d $__kdt_h:$__kdt_mi:$__kdt_s.$__kdt_ms"
                    break 4
                fi
            done
        done
    done
done
# Explicit leap-day edges that the {1,15,28} sample skips.
for edge in "2000 2 29 0 0 0 0" "2004 2 29 23 59 59 999" "1996 2 29 6 0 0 1" \
            "2000 12 31 0 0 0 0" "1899 12 30 0 0 0 0"; do
    read -r y mo d h mi s ms <<< "$edge"
    dateutils._join_kdt "$y" "$mo" "$d" "$h" "$mi" "$s" "$ms"; kdt="$REPLY"
    unset __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
    dateutils._split_kdt "$kdt"
    grid_count=$((grid_count + 1))
    if [[ "$__kdt_y $__kdt_mo $__kdt_d $__kdt_h $__kdt_mi $__kdt_s $__kdt_ms" \
          != "$y $mo $d $h $mi $s $ms" ]]; then
        grid_fail="edge $edge -> $__kdt_y-$__kdt_mo-$__kdt_d ..."
        break
    fi
done
if [[ -z "$grid_fail" ]]; then
    kt_test_pass "KDT join/split roundtrip over the sampled grid ($grid_count cases)"
else
    kt_test_fail "KDT roundtrip mismatch: $grid_fail"
fi

# ---------------------------------------------------------------------------
# 2. Anchors: KDT 0 = 1970-01-01 Thursday; negative KDT; Pascal epoch
# ---------------------------------------------------------------------------
kt_test_start "KDT 0 == 1970-01-01 00:00:00.000"
unset __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
dateutils._split_kdt 0
if [[ "$__kdt_y-$__kdt_mo-$__kdt_d $__kdt_h:$__kdt_mi:$__kdt_s.$__kdt_ms" == "1970-1-1 0:0:0.0" ]]; then
    kt_test_pass "KDT 0 == 1970-01-01 00:00:00.000"
else
    kt_test_fail "KDT 0 got $__kdt_y-$__kdt_mo-$__kdt_d $__kdt_h:$__kdt_mi:$__kdt_s.$__kdt_ms"
fi

kt_test_start "1970-01-01 is a Thursday (ISO weekday 4)"
dateutils._weekday_iso 0
if [[ "$REPLY" == "4" ]]; then
    kt_test_pass "1970-01-01 is a Thursday (ISO weekday 4)"
else
    kt_test_fail "weekday(0) = $REPLY, want 4"
fi

kt_test_start "KDT -1 == 1969-12-31 23:59:59.999 (floor division for pre-1970)"
unset __kdt_y __kdt_mo __kdt_d __kdt_h __kdt_mi __kdt_s __kdt_ms
dateutils._split_kdt -1
if [[ "$__kdt_y-$__kdt_mo-$__kdt_d $__kdt_h:$__kdt_mi:$__kdt_s.$__kdt_ms" == "1969-12-31 23:59:59.999" ]]; then
    kt_test_pass "KDT -1 == 1969-12-31 23:59:59.999"
else
    kt_test_fail "KDT -1 got $__kdt_y-$__kdt_mo-$__kdt_d $__kdt_h:$__kdt_mi:$__kdt_s.$__kdt_ms"
fi

kt_test_start "Pascal epoch 1899-12-30 == KDT -2209161600000"
dateutils._join_kdt 1899 12 30 0 0 0 0
if [[ "$REPLY" == "-2209161600000" ]]; then
    kt_test_pass "Pascal epoch 1899-12-30 == KDT -2209161600000"
else
    kt_test_fail "1899-12-30 got KDT $REPLY, want -2209161600000"
fi

# ---------------------------------------------------------------------------
# 3. ISO 8601 format / parse
# ---------------------------------------------------------------------------
kt_test_start "_fmt_datetime anchors"
dateutils._fmt_datetime 0;  a="$REPLY"
dateutils._fmt_datetime -1; b="$REPLY"
dateutils._join_kdt 2011 3 26 19 15 30 555
dateutils._fmt_datetime "$REPLY"; c="$REPLY"
if [[ "$a" == "1970-01-01 00:00:00.000" && "$b" == "1969-12-31 23:59:59.999" \
   && "$c" == "2011-03-26 19:15:30.555" ]]; then
    kt_test_pass "_fmt_datetime anchors"
else
    kt_test_fail "_fmt_datetime got [$a] [$b] [$c]"
fi

kt_test_start "parse(fmt(kdt)) == kdt roundtrip over a KDT grid"
iso_fail=""
for kdt in 0 -1 1 1000 86399999 -86400000 1301166930555 -2209161600000 1783728000000; do
    dateutils._fmt_datetime "$kdt"; s="$REPLY"
    if dateutils._parse_iso "$s"; then
        [[ "$REPLY" == "$kdt" ]] || { iso_fail="$kdt -> [$s] -> $REPLY"; break; }
    else
        iso_fail="$kdt -> [$s] parse failed"; break
    fi
done
if [[ -z "$iso_fail" ]]; then
    kt_test_pass "parse(fmt(kdt)) == kdt roundtrip over a KDT grid"
else
    kt_test_fail "ISO roundtrip: $iso_fail"
fi

kt_test_start "_parse_iso accepts T-separator, date-only, and seconds-only forms"
ok=true
dateutils._parse_iso "2011-03-26T19:15:30.555" && [[ "$REPLY" == 1301166930555 ]] || ok=false
dateutils._parse_iso "2011-03-26" && [[ "$REPLY" == 1301097600000 ]] || ok=false   # 00:00:00.000
dateutils._parse_iso "2011-03-26 19:15:30" && [[ "$REPLY" == 1301166930000 ]] || ok=false
if $ok; then
    kt_test_pass "_parse_iso accepts T-separator, date-only, and seconds-only forms"
else
    kt_test_fail "_parse_iso form handling wrong (last REPLY=$REPLY)"
fi

kt_test_start "_parse_iso captures the trailing zone (Z and +hh:mm) for P6"
ok=true
dateutils._parse_iso "2011-03-26T19:15:30Z"       && [[ "$__kdt_has_tz" == 1 && "$__kdt_tzoff_min" == 0    ]] || ok=false
dateutils._parse_iso "2011-03-26T19:15:30+03:00"  && [[ "$__kdt_has_tz" == 1 && "$__kdt_tzoff_min" == 180  ]] || ok=false
dateutils._parse_iso "2011-03-26T19:15:30-0530"   && [[ "$__kdt_has_tz" == 1 && "$__kdt_tzoff_min" == -330 ]] || ok=false
dateutils._parse_iso "2011-03-26T19:15:30"        && [[ "$__kdt_has_tz" == 0 ]] || ok=false
if $ok; then
    kt_test_pass "_parse_iso captures the trailing zone (Z and +hh:mm) for P6"
else
    kt_test_fail "_parse_iso zone capture wrong (has_tz=$__kdt_has_tz off=$__kdt_tzoff_min)"
fi

kt_test_start "_parse_iso rejects malformed input (returns status 1)"
ok=true; badval=""
for bad in "2011-13-01" "2011-02-30T25:00:00" "not-a-date" "2011/03/26" "2011-03-26 19:60:00" ""; do
    if dateutils._parse_iso "$bad"; then ok=false; badval="$bad"; break; fi
done
if $ok; then
    kt_test_pass "_parse_iso rejects malformed input (returns status 1)"
else
    kt_test_fail "_parse_iso accepted malformed input: [$badval]"
fi

# ---------------------------------------------------------------------------
# 4. Wall clock (zero forks)
# ---------------------------------------------------------------------------
kt_test_start "now() within 2s of an independent EPOCHREALTIME+offset computation"
ref_secs="${EPOCHREALTIME%[.,]*}"
printf -v z '%(%z)T' -1
off_s=$(( 10#${z:1:2}*3600 + 10#${z:3:2}*60 )); [[ "${z:0:1}" == "-" ]] && off_s=$(( -off_s ))
ref_ms=$(( (ref_secs + off_s) * 1000 ))
now_ms=$(dateutils.now)
delta=$(( now_ms - ref_ms )); (( delta < 0 )) && delta=$(( -delta ))
if (( delta <= 2000 )); then
    kt_test_pass "now() within 2s of an independent EPOCHREALTIME+offset computation"
else
    kt_test_fail "now()=$now_ms vs ref=$ref_ms, delta=${delta}ms"
fi

kt_test_start "now() - nowUTC() == local offset"
u=$(dateutils.nowUTC); n=$(dateutils.now)
printf -v z '%(%z)T' -1
off_ms=$(( (10#${z:1:2}*3600 + 10#${z:3:2}*60) * 1000 )); [[ "${z:0:1}" == "-" ]] && off_ms=$(( -off_ms ))
diff=$(( n - u )); d2=$(( diff - off_ms )); (( d2 < 0 )) && d2=$(( -d2 ))
# allow 1s slack for the two separate samplings
if (( d2 <= 1000 )); then
    kt_test_pass "now() - nowUTC() == local offset"
else
    kt_test_fail "now-nowUTC=$diff, offset=$off_ms"
fi

kt_test_start "today() == dateOf(now()); yesterday/tomorrow are ±1 day"
t=$(dateutils.today)
dn=$(dateutils.dateOf "$(dateutils.now)")
yd=$(dateutils.yesterday); tm=$(dateutils.tomorrow)
if [[ "$t" == "$dn" ]] && (( yd == t - 86400000 )) && (( tm == t + 86400000 )); then
    kt_test_pass "today() == dateOf(now()); yesterday/tomorrow are ±1 day"
else
    kt_test_fail "today=$t dateOf(now)=$dn yesterday=$yd tomorrow=$tm"
fi

# ---------------------------------------------------------------------------
# 5. dateOf / timeOf decomposition
# ---------------------------------------------------------------------------
kt_test_start "dateOf(kdt) + timeOf(kdt) == kdt, timeOf in [0, MS_PER_DAY)"
ok=true
for kdt in 0 -1 1301166930555 -2209161600000 86399999 -86400001; do
    do_=$(dateutils.dateOf "$kdt"); to=$(dateutils.timeOf "$kdt")
    (( do_ + to == kdt )) || { ok=false; break; }
    (( to >= 0 && to < 86400000 )) || { ok=false; break; }
    (( do_ % 86400000 == 0 )) || { ok=false; break; }
done
if $ok; then
    kt_test_pass "dateOf(kdt) + timeOf(kdt) == kdt, timeOf in [0, MS_PER_DAY)"
else
    kt_test_fail "dateOf/timeOf decomposition wrong at kdt=$kdt (dateOf=$do_ timeOf=$to)"
fi

# ---------------------------------------------------------------------------
# 6. Constant getters
# ---------------------------------------------------------------------------
kt_test_start "constant getters return the __KDT_* values"
if [[ "$(dateutils.msPerSecond)" == 1000 && "$(dateutils.msPerMinute)" == 60000 \
   && "$(dateutils.msPerHour)" == 3600000 && "$(dateutils.msPerDay)" == 86400000 \
   && "$(dateutils.msPerWeek)" == 604800000 \
   && "$(dateutils.approxMsPerMonth)" == 2629800000 \
   && "$(dateutils.approxMsPerYear)" == 31557600000 \
   && "$(dateutils.approxDaysPerMonth)" == "30.4375" \
   && "$(dateutils.approxDaysPerYear)" == "365.25" ]]; then
    kt_test_pass "constant getters return the __KDT_* values"
else
    kt_test_fail "constant getter mismatch"
fi

kt_test_start "__KDT_* constants are readonly (writes fail loudly)"
if (__KDT_MS_PER_DAY=1) 2>/dev/null; then
    kt_test_fail "__KDT_MS_PER_DAY write unexpectedly succeeded"
else
    kt_test_pass "__KDT_* constants are readonly (writes fail loudly)"
fi

# ---------------------------------------------------------------------------
# 7. Perf / shape contracts
# ---------------------------------------------------------------------------
kt_test_start "dateutils dispatchers are thin (no capture overhead)"
decl="$(declare -f dateutils.now)"
if [[ "$decl" == *"__kk_static_out"* || "$decl" == *'REPLY=${'* ]]; then
    kt_test_fail "capturing dispatcher found — a static var crept in?"
else
    kt_test_pass "dateutils dispatchers are thin (no capture overhead)"
fi

kt_test_start "hot paths make zero forks (work with an empty PATH)"
# Any external-command fork would fail with PATH unset; only builtins survive.
if out=$( PATH=''; dateutils.nowUTC ) && [[ "$out" =~ ^[0-9]+$ ]] \
   && out2=$( PATH=''; dateutils.dateOf 1301166930555 ) && [[ "$out2" == 1301097600000 ]] \
   && out3=$( PATH=''; dateutils.today ) && [[ "$out3" =~ ^[0-9]+$ ]]; then
    kt_test_pass "hot paths make zero forks (work with an empty PATH)"
else
    kt_test_fail "a hot path forked (empty-PATH run failed): [$out] [$out2] [$out3]"
fi

kt_test_start "kklass metadata lists the P0 static methods"
expected=(now nowUTC today dateOf timeOf msPerDay approxDaysPerYear)
missing=()
for m in "${expected[@]}"; do
    found=false
    for r in "${dateutils_class_static_methods[@]}"; do [[ "$r" == "$m" ]] && { found=true; break; }; done
    $found || missing+=("$m")
done
if (( ${#dateutils_class_static_methods[@]} > 0 && ${#missing[@]} == 0 )); then
    kt_test_pass "kklass metadata lists the P0 static methods"
else
    kt_test_fail "metadata missing: ${missing[*]:-(none)}; count ${#dateutils_class_static_methods[@]}"
fi
