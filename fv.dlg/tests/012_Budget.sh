#!/usr/bin/env bash
# 012_Budget.sh - design §6.1, the boxes (4a-1; the lists come with 4a-2):
# kklass dispatches and fv.video writes of one fv.dlg.run --fv-headless
# call, the application made ... deleted (80 x 24, the scripted terminal,
# the test lib's counting shims), each logged ("# calls" / "# writes"):
#   msgbox Enter 22 / 16, yesno Enter 24 / 16, infobox (no loop) 20 / 12,
#   inputbox / passwordbox `abc` Enter 26 / 20;
# per key in a box or the input line (the difference to the same call with
# fewer keys, divided by their count): at most 2 dispatches / 2 writes
# (design: 0 / 1; a focus move between two buttons: 4 writes, measured 3);
# with --backtitle and with NO_COLOR logged (the
# backtitle's Draw is an override: one dispatch per draw; NO_COLOR's
# palette calls: their cost logged).
# Fork-free per key: 001 (PATH='' and the static scan); times: the CI
# bench (stage 4e).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"

# count SPEC... -- ARG... : one call with both counters on; C / W
count() {
    local -a specs=()
    while (( $# )) && [ "$1" != -- ]; do specs+=("$1"); shift; done
    shift
    fvdl_events "${specs[@]}"
    fvw_count_on; fvw_writes_on
    FVW_CALLS=0 FVW_WRITES=0
    fv.dlg.run --fv-headless "$@"
    R=$? C=$FVW_CALLS W=$FVW_WRITES
    fvw_count_off; fvw_writes_off
    fva_noevents; __FV_VW_EOF=0
}
# budget LABEL LIMITC LIMITW SPEC... -- ARG... — one test, logged
budget() {
    local l=$1 lc=$2 lw=$3
    shift 3
    count "$@"
    kt_test_log "# calls $l $C"
    kt_test_log "# writes $l $W"
    kt_test_start "budget $l: at most $lc dispatches / $lw writes"
    if (( C <= lc && W <= lw )); then kt_test_pass "$C dispatches, $W writes (rc $R)"; else kt_test_fail "$C dispatches, $W writes > $lc / $lw (rc $R)"; fi
}
# perkey LABEL N WL SPEC_FEW... -- SPEC_MORE... -- ARG... — the cost of the N
# keys SPEC_MORE has more than SPEC_FEW: at most 2 dispatches / WL writes per
# key, logged
perkey() {
    local l=$1 n=$2 wl=$3 c0 w0
    shift 3
    local -a few=() more=()
    while [ "$1" != -- ]; do few+=("$1"); shift; done
    shift
    while [ "$1" != -- ]; do more+=("$1"); shift; done
    count "${few[@]}" "$@"; c0=$C w0=$W
    count "${more[@]}" "$@"
    local dc=$(( C - c0 )) dw=$(( W - w0 ))
    kt_test_log "# calls $l/key $(( dc / n )) ($dc for $n)"
    kt_test_log "# writes $l/key $(( dw / n )) ($dw for $n)"
    kt_test_start "per key, $l: at most 2 dispatches / $wl writes"
    if (( dc <= 2 * n && dw <= wl * n )); then kt_test_pass "$dc dispatches, $dw writes for $n keys"; else kt_test_fail "$dc dispatches, $dw writes for $n keys"; fi
}

kt_test_section "012: the boxes (design §6.1)"
budget msgbox.enter 22 16 'key kbEnter' -- --msgbox 'Hello, world!' 0 0
budget yesno.enter 24 16 'key kbEnter' -- --yesno 'Proceed?' 0 0
budget infobox 20 12 -- --infobox 'Please wait' 0 0
budget inputbox.abc 26 20 'char a' 'char b' 'char c' 'key kbEnter' -- --inputbox 'Name:' 0 0
budget passwordbox.abc 26 20 'char a' 'char b' 'char c' 'key kbEnter' -- --passwordbox 'Password:' 0 0
budget inputbox.init.enter 26 20 'key kbEnter' -- --inputbox 'Name:' 0 0 init

kt_test_section "012: per key"
perkey inputbox.char 5 2 'key kbEnter' -- 'char a' 'char b' 'char c' 'char d' 'char e' 'key kbEnter' -- --inputbox 'Name:' 0 0
perkey inputbox.cursor 4 2 'key kbEnter' -- 'key kbLeft' 'key kbLeft' 'key kbRight' 'key kbHome' 'key kbEnter' -- --inputbox 'Name:' 0 0 abc
# (a focus move between the two buttons: both redrawn and the default
# mark moved by cmGrabDefault / cmReleaseDefault — fv.dialogs' P3 work,
# 3 writes; the design's 2 / 2 is for a key inside a control)
perkey yesno.tab 4 4 'key kbEnter' -- 'key kbTab' 'key kbTab' 'key kbTab' 'key kbTab' 'key kbEnter' -- --yesno 'Proceed?' 0 0
perkey msgbox.unused 4 2 'key kbEnter' -- 'key kbF2' 'key kbF3' 'char z' 'key kbUp' 'key kbEnter' -- --msgbox 'Hello' 0 0

kt_test_section "012: logged"
count 'key kbEnter' -- --backtitle 'Setup' --msgbox 'Hello, world!' 0 0
kt_test_log "# calls msgbox.backtitle $C"
kt_test_log "# writes msgbox.backtitle $W"
c1=$C
NO_COLOR=1 count 'key kbEnter' -- --msgbox 'Hello, world!' 0 0
kt_test_log "# calls msgbox.nocolor $C"
kt_test_log "# writes msgbox.nocolor $W"
kt_test_start "--backtitle and NO_COLOR counted (logged; --backtitle within the msgbox limit + 2)"
if (( c1 <= 24 )); then kt_test_pass "backtitle $c1, NO_COLOR $C dispatches"; else kt_test_fail "backtitle $c1"; fi

kt_test_log "012_Budget.sh completed"
