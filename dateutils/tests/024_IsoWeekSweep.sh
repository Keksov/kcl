#!/bin/bash
# 024_IsoWeekSweep.sh — the ISO calendar cross-checked against perl.
#
# The reviewer's `repro/g3/r3_isoweek.sh` walked all 15 006 days of 1995..2035
# and compared `_decode_date_week`, `_weekday_iso`, day-of-year and the
# encode/decode round trip against perl's `%G %V %u %j`. It found 0 mismatches —
# and it is the only thing that would catch a one-day drift in the ISO-week
# algorithm, which six hand-picked fixtures cannot.
#
# It costs ~40 s, so it runs in two sizes:
#
#   default            every 37th day of 1900..2100 (about 2000 days) — enough
#                      to hit every weekday, every month and both week-53 rules;
#   KCL_SLOW_TESTS=1   every single day of 1900..2100 (73 414 days).
#
# The perl side is ONE process in both cases; the cost is the bash loop.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

kt_test_init "IsoWeekSweep" "$SCRIPT_DIR" "$@"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$UNIT_DIR/dateutils.sh"

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
REF="$TMP/perl_week.txt"

FIRST_DAY=-25567      # 1900-01-01 as a day number (days since 1970-01-01)
LAST_DAY=47846        # 2100-12-31
if [[ "${KCL_SLOW_TESTS:-}" == "1" ]]; then
    STEP=1
else
    STEP=37
fi

kt_test_start "the perl reference for the sweep is produced"
if perl -MPOSIX -e '
    my ($first, $last, $step) = @ARGV;
    for (my $d = $first; $d <= $last; $d += $step) {
        my @t = gmtime($d * 86400);
        print $d, " ", strftime("%G %V %u %j", @t), "\n";
    }' -- "$FIRST_DAY" "$LAST_DAY" "$STEP" > "$REF" 2>"$TMP/perl.err"; then
    lines=$(wc -l < "$REF")
    if (( lines > 100 )); then
        kt_test_pass "$lines reference days (step $STEP)"
    else
        kt_test_fail "perl produced only $lines lines"
    fi
else
    kt_test_fail "perl failed: $(<"$TMP/perl.err")"
fi

kt_test_start "ISO year/week/weekday and day-of-year match perl over 1900..2100"
bad=0; n=0; firstbad=""
while read -r day gy gw gu gj; do
    kdt=$(( day * 86400000 + 13 * 3600000 ))     # 13:00, so the time never matters
    n=$(( n + 1 ))
    dateutils._decode_date_week "$kdt"
    if (( __kdt_wy_year != 10#$gy || __kdt_wy_week != 10#$gw || __kdt_wy_dow != 10#$gu )); then
        bad=$(( bad + 1 ))
        [[ -z "$firstbad" ]] && firstbad="week day=$day want $gy/$gw/$gu got $__kdt_wy_year/$__kdt_wy_week/$__kdt_wy_dow"
    fi
    dateutils._weekday_iso "$kdt"
    if (( REPLY != 10#$gu )); then
        bad=$(( bad + 1 ))
        [[ -z "$firstbad" ]] && firstbad="dow day=$day want $gu got $REPLY"
    fi
    dateutils._split_kdt "$kdt"
    dateutils._days_from_civil "$__kdt_y" 1 1
    if (( day - REPLY + 1 != 10#$gj )); then
        bad=$(( bad + 1 ))
        [[ -z "$firstbad" ]] && firstbad="doy day=$day want $gj got $(( day - REPLY + 1 ))"
    fi
done < "$REF"
if (( bad == 0 && n > 100 )); then
    kt_test_pass "$n days, 0 mismatches"
else
    kt_test_fail "$n days, $bad mismatches; first: $firstbad"
fi

kt_test_start "encodeDateWeek(decodeDateWeek(d)) == d for every sampled day"
bad=0; n=0; firstbad=""
while read -r day _ _ _ _; do
    kdt=$(( day * 86400000 ))
    n=$(( n + 1 ))
    dateutils._decode_date_week "$kdt"
    if ! dateutils._encode_date_week "$__kdt_wy_year" "$__kdt_wy_week" "$__kdt_wy_dow"; then
        bad=$(( bad + 1 ))
        [[ -z "$firstbad" ]] && firstbad="encode refused $__kdt_wy_year/$__kdt_wy_week/$__kdt_wy_dow (day $day)"
        continue
    fi
    if (( REPLY != kdt )); then
        bad=$(( bad + 1 ))
        [[ -z "$firstbad" ]] && firstbad="round trip day=$day got $(( REPLY / 86400000 ))"
    fi
done < "$REF"
if (( bad == 0 && n > 100 )); then
    kt_test_pass "$n round trips, 0 mismatches"
else
    kt_test_fail "$n round trips, $bad mismatches; first: $firstbad"
fi

kt_test_start "weeksInAYear matches perl for every year 1900..2100"
# Dec 28 is always in the last ISO week of its own year.
perl -MPOSIX -e '
    for my $y (1900 .. 2100) {
        # days from 1970-01-01 to Dec 28 of $y, via the civil algorithm
        my ($yy, $m, $d) = ($y, 12, 28);
        $yy -= ($m <= 2) ? 1 : 0;
        my $era = ($yy >= 0 ? $yy : $yy - 399) / 400; $era = int($era);
        my $yoe = $yy - $era * 400;
        my $doy = int((153 * ($m > 2 ? $m - 3 : $m + 9) + 2) / 5) + $d - 1;
        my $doe = $yoe * 365 + int($yoe / 4) - int($yoe / 100) + $doy;
        my $days = $era * 146097 + $doe - 719468;
        my @t = gmtime($days * 86400);
        print $y, " ", strftime("%V", @t), "\n";
    }' > "$TMP/perl_wiy.txt" 2>"$TMP/perl.err"
bad=0; n=0; firstbad=""
while read -r y w; do
    n=$(( n + 1 ))
    dateutils._weeks_in_year "$y"
    if (( REPLY != 10#$w )); then
        bad=$(( bad + 1 ))
        [[ -z "$firstbad" ]] && firstbad="year $y want $w got $REPLY"
    fi
done < "$TMP/perl_wiy.txt"
if (( bad == 0 && n == 201 )); then
    kt_test_pass "201 years, 0 mismatches"
else
    kt_test_fail "$n years, $bad mismatches; first: $firstbad"
fi

kt_test_start "the slow variant is reachable (KCL_SLOW_TESTS=1 raises the day count)"
if [[ "${KCL_SLOW_TESTS:-}" == "1" ]]; then
    if (( STEP == 1 )); then
        kt_test_pass "slow mode: step 1, every day of 1900..2100"
    else
        kt_test_fail "KCL_SLOW_TESTS=1 did not select step 1"
    fi
else
    if (( STEP == 37 )); then
        kt_test_pass "sampled mode: step 37 (set KCL_SLOW_TESTS=1 for all 73 414 days)"
    else
        kt_test_fail "default mode did not select step 37"
    fi
fi
