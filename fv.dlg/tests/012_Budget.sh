#!/usr/bin/env bash
# 012_Budget.sh - design §6.1, the boxes (4a-1) and the lists (4a-2):
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

kt_test_section "012: the lists (4a-2, design §6.1)"
L=(a Apple b Banana c Cherry d Date e Elder f Fig g Grape h Hazel)
LC=(a Apple off b Banana off c Cherry off d Date off e Elder off)
budget menu.down2.enter 36 20 'key kbDown' 'key kbDown' 'key kbEnter' -- --menu 'Pick' 0 0 0 "${L[@]}"
budget checklist.sds.enter 40 20 'char _' 'key kbDown' 'char _' 'key kbEnter' -- --checklist 'Pick' 0 0 0 "${LC[@]}"
budget radiolist.sds.enter 40 20 'char _' 'key kbDown' 'char _' 'key kbEnter' -- --radiolist 'Pick' 0 0 0 "${LC[@]}"
budget menu.scrolltext.pgdn 36 20 'key kbPgDn' 'key kbEnter' -- --msgbox "$(printf 'l%d\\n' {1..30})" 8 30
# per key on a list: at most 1 dispatch / 3 writes (§6.1 says 3 / 3; L5:
# measured 0 — TDlgList's HandleEvent / SelectItem bodies run through fv.views'
# elision; a lost registration shows at the Space keys (2 kklass dispatches
# per key: HandleEvent + SelectItem) and in 001's registration check)
perkey3() {
    local l=$1 n=$2 c0 w0
    shift 2
    local -a few=() more=()
    while [ "$1" != -- ]; do few+=("$1"); shift; done
    shift
    while [ "$1" != -- ]; do more+=("$1"); shift; done
    count "${few[@]}" "$@"; c0=$C w0=$W
    count "${more[@]}" "$@"
    local dc=$(( C - c0 )) dw=$(( W - w0 ))
    kt_test_log "# calls $l/key $(( dc / n )) ($dc for $n)"
    kt_test_log "# writes $l/key $(( dw / n )) ($dw for $n)"
    kt_test_start "per key, $l: at most 1 dispatch / 3 writes"
    if (( dc <= n && dw <= 3 * n )); then kt_test_pass "$dc dispatches, $dw writes for $n keys"; else kt_test_fail "$dc dispatches, $dw writes for $n keys"; fi
}
perkey3 list.down 4 'key kbEnter' -- 'key kbDown' 'key kbDown' 'key kbDown' 'key kbDown' 'key kbEnter' -- --menu 'Pick' 0 0 4 "${L[@]}"
perkey3 list.pgdn 2 'key kbEnter' -- 'key kbPgDn' 'key kbPgDn' 'key kbEnter' -- --menu 'Pick' 0 0 3 "${L[@]}"
perkey3 list.space 4 'key kbEnter' -- 'char _' 'char _' 'char _' 'char _' 'key kbEnter' -- --checklist 'Pick' 0 0 0 "${LC[@]}"
perkey3 radio.space 4 'key kbEnter' -- 'char _' 'key kbDown' 'char _' 'key kbUp' 'key kbEnter' -- --radiolist 'Pick' 0 0 0 "${LC[@]}"
perkey3 list.letter 4 'key kbEnter' -- 'char c' 'char e' 'char a' 'char z' 'key kbEnter' -- --menu 'Pick' 0 0 0 "${L[@]}"
perkey3 text.scroll 4 'key kbEnter' -- 'key kbDown' 'key kbDown' 'key kbPgDn' 'key kbUp' 'key kbEnter' -- --msgbox "$(printf 'l%d\\n' {1..30})" 8 30
# (a double click: the press, focused + selected; its release)
perkey3 checklist.dblclick 2 'key kbEnter' -- 'dbl 30 11' 'up 30 11' 'key kbEnter' -- --checklist 'Pick' 0 0 0 "${LC[@]}"
count 'dbl 30 10' -- --menu 'Pick' 0 0 0 "${L[@]}"
kt_test_log "# calls menu.dblclick $C"
kt_test_log "# writes menu.dblclick $W"
kt_test_start "a double click on a menu item ends it (rc 0) within the menu's limit 36 / 20"
if (( R == 0 && C <= 36 && W <= 20 )); then kt_test_pass "$C dispatches, $W writes"; else kt_test_fail "rc $R, $C dispatches, $W writes"; fi
BIG=()
for (( i = 0; i < 10000; i++ )); do BIG+=("t$i" "item $i" off); done
budget checklist.10000.end.space 40 20 'key kbEnd' 'char _' 'key kbEnter' -- --checklist 'Big' 0 0 0 "${BIG[@]}"
unset BIG

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
