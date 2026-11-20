#!/usr/bin/env bash
# 025_Quiet.sh - the broadcast table (P3 design 10.3, stage 3a-2):
# __FV_VW_BCAST[BODY]="cmA cmB ..." names the broadcasts each built-in
# HandleEvent body reacts to; the dispatch and fv.views._quiet skip, without
# a call, a view whose handler is a body with a row that does not list the
# command (a group: when its subtree has no listener either):
#   * the rows of fv.views' own bodies give exactly the hard-coded rules they
#     replace (TView, TFrame, TGroup: none; TWindow: cmSelectWindowNum); a
#     QGRP entry counts as the row '';
#   * the table against a full dispatch (the table emptied: every handler
#     whose EventMask lets the broadcast through is called) on seeded random
#     trees of plain views, frames, windows, groups, built-in bodies of this
#     test (a leaf reacting to cmA cmB, a group reacting to cmC) and user
#     views interleaved (listeners that may handle a broadcast, a user group,
#     a user override of a built-in body): through fv.views.message and
#     through the group's HandleEvent, the same reactions in the same order,
#     each seeing its owner's Phase, the same handler, at most as many
#     dispatches;
#   * adding a row: a built-in body without a row is called for every
#     broadcast; with a row only for the commands listed; the row removed,
#     every one again;
#   * an override of a built-in body is always called; a subclass that
#     inherits the body follows the body's row;
#   * the dialog scene (fvw_dscene): a Tab between the controls reaches a
#     listening label-like leaf with both focus broadcasts and never a
#     built-in leaf whose row lacks them.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvw_testlib.sh"
fvw_init "$(basename "$0" .sh)" "$@"

kt_test_section "025: the broadcast table (P3 10.3)"

# ---- the test's classes ---------------------------------------------------------
QLOG='' QB_CALLS=0 QN_CALLS=0
declare -A QL_EAT=()
fvq_note() {   # V TAG: the reaction, with the owner's Phase
    local -n __q_d=${1}_data
    local o=${__q_d[Owner]-}
    local p=''
    if [[ -n $o ]]; then local -n __q_o=${o}_data; p=${__q_o[Phase]-}; fi
    QLOG+="$1$2$FV_EV_COMMAND@$p;"
}
# a user listener: notes every broadcast; handles the one in QL_EAT[V]
class TQL : TView
    public
        override proc HandleEvent
end
TQL.HandleEvent() {
    if [ "$FV_EV_WHAT" = evBroadcast ]; then
        fvq_note "$this" '<'
        if [ "${QL_EAT[$this]-}" = "$FV_EV_COMMAND" ]; then fv.views.clearEvent "$this"; fi
    fi
}
build TQL
# a built-in body of this test (registered in the elision table): reacts to
# cmA and cmB (handles cmB when QB_EAT is set), counts its calls
fvq_bEvent() {
    QB_CALLS=$(( QB_CALLS + 1 ))
    if [ "$FV_EV_WHAT" = evBroadcast ] && { [ "$FV_EV_COMMAND" = cmA ] || [ "$FV_EV_COMMAND" = cmB ]; }; then
        fvq_note "$1" '#'
        if [ "$FV_EV_COMMAND" = cmB ] && [[ -n ${QB_EAT-} ]]; then fv.views.clearEvent "$1"; fi
    fi
    return 0
}
class TQB : TView
    public
        nofields override proc HandleEvent
end
TQB.HandleEvent() { fvq_bEvent "$this" || return; }
build TQB
# a user override of TQB's body (always called) and a subclass inheriting it
class TQD : TQB
    public
        override proc HandleEvent
end
TQD.HandleEvent() { if [ "$FV_EV_WHAT" = evBroadcast ]; then fvq_note "$this" '~'; fi; inherited HandleEvent "$@"; }
build TQD
class TQE : TQB
end
build TQE
# a built-in group body of this test: TGroup's, then reacts to cmC
fvq_gEvent() {
    fv.views._groupEvent "$1"
    if [ "$FV_EV_WHAT" = evBroadcast ] && [ "$FV_EV_COMMAND" = cmC ]; then fvq_note "$1" '%'; fi
    return 0
}
class TQG : TGroup
    public
        nofields override proc HandleEvent
end
TQG.HandleEvent() { fvq_gEvent "$this" || return; }
build TQG
# a user group: inherited, then notes every broadcast
class TQU : TGroup
    public
        override proc HandleEvent
end
TQU.HandleEvent() { inherited HandleEvent "$@"; if [ "$FV_EV_WHAT" = evBroadcast ]; then fvq_note "$this" '!'; fi; }
build TQU
# a built-in body without a row (for "adding a row")
fvq_nEvent() { QN_CALLS=$(( QN_CALLS + 1 )); if [ "$FV_EV_WHAT" = evBroadcast ]; then fvq_note "$1" '^'; fi; return 0; }
class TQN : TView
    public
        nofields override proc HandleEvent
end
TQN.HandleEvent() { fvq_nEvent "$this" || return; }
build TQN
__FV_VW_IMPL[TQB.HandleEvent]=fvq_bEvent __FV_VW_IMPL[TQG.HandleEvent]=fvq_gEvent __FV_VW_IMPL[TQN.HandleEvent]=fvq_nEvent
__FV_VW_BCAST[fvq_bEvent]='cmA cmB' __FV_VW_BCAST[fvq_gEvent]='cmC'
listen() { local -n __q_d=${1}_data; __q_d[EventMask]=$(( __q_d[EventMask] | FV_EM_BROADCAST )); }
deaf() { local -n __q_d=${1}_data; __q_d[EventMask]=$(( __q_d[EventMask] & ~FV_EM_BROADCAST )); }

kt_test_start "fv.views' rows give the rules they replace: TView, TFrame, TGroup none, TWindow cmSelectWindowNum; QGRP counts as ''"
r="[${__FV_VW_BCAST[fv.views._viewEvent]-x}][${__FV_VW_BCAST[fv.views._frameEvent]-x}][${__FV_VW_BCAST[fv.views._groupEvent]-x}][${__FV_VW_BCAST[fv.views._windowEvent]-x}]"
TGroup.new tg 0 0 20 10
TWindow.new tw 0 0 20 8 'T' 1
TView.new tv 0 0 2 1; listen tv
fv.views.insert tw tv
fv.views.insert tg tw
q=''
for c in cmA cmSelectWindowNum; do fv.views._quiet tg "$c"; q+=$?; fv.views._quiet tw "$c"; q+=$?; fv.views._quiet tv "$c"; q+=$?; done
fvq_xEvent() { fv.views._groupEvent "$1"; }
class TQX : TGroup
    public
        nofields override proc HandleEvent
end
TQX.HandleEvent() { fvq_xEvent "$this" || return; }
build TQX
__FV_VW_IMPL[TQX.HandleEvent]=fvq_xEvent
TQX.new tx 0 0 5 5; fv.views.insert tg tx
fv.views._quiet tx cmA; q+=" $?"
__FV_VW_QGRP[fvq_xEvent]=1
fv.views._quiet tx cmA; q+=$?
unset '__FV_VW_QGRP[fvq_xEvent]'
tg.delete
if [[ "$r $q" == '[][][][cmSelectWindowNum] 000110 10' ]]; then kt_test_pass "ok"; else kt_test_fail "rows $r quiet $q"; fi

# ---- the table against a full dispatch on random trees ------------------------------
QN=0
qmk() {   # GROUP DEPTH: 2-5 random subviews into GROUP
    local g=$1 d=$2 n i k v
    n=$(( 2 + RANDOM % 4 ))
    for (( i = 0; i < n; i++ )); do
        QN=$(( QN + 1 )) v=q$QN
        if (( d < 2 )); then k=$(( RANDOM % 10 )); else k=$(( RANDOM % 6 )); fi
        case $k in
            0) TView.new "$v" 0 0 3 1; (( RANDOM % 3 )) || listen "$v" ;;
            1) TQL.new "$v" 0 0 3 1; (( RANDOM % 4 )) && listen "$v"; (( RANDOM % 5 )) || QL_EAT[$v]=$(( RANDOM % 2 )) ;;
            2) TQB.new "$v" 0 0 3 1; (( RANDOM % 4 )) && listen "$v" ;;
            3) TQD.new "$v" 0 0 3 1; (( RANDOM % 4 )) && listen "$v" ;;
            4) TQE.new "$v" 0 0 3 1; (( RANDOM % 4 )) && listen "$v" ;;
            5) TQL.new "$v" 0 0 3 1; listen "$v"; local -n __q_s=${v}_data; __q_s[State]=$(( __q_s[State] | FV_SF_DISABLED )); unset -n __q_s ;;
            6) TGroup.new "$v" 0 0 10 5; qmk "$v" $(( d + 1 )); (( RANDOM % 5 )) || deaf "$v" ;;
            7) TQG.new "$v" 0 0 10 5; qmk "$v" $(( d + 1 )) ;;
            8) TWindow.new "$v" 0 0 20 8 "w$v" 0; qmk "$v" $(( d + 1 )) ;;
            9) TQU.new "$v" 0 0 10 5; qmk "$v" $(( d + 1 )) ;;
        esac
        # (QL_EAT 0 / 1 -> the command it handles)
        if [[ ${QL_EAT[$v]-} == [01] ]]; then if (( QL_EAT[$v] )); then QL_EAT[$v]=cmB; else QL_EAT[$v]=cmC; fi; fi
        fv.views.insert "$g" "$v"
    done
}
# qrun HOW CMD -> REPLY = what happened: the reactions, the outcome
qrun() {
    local rc
    QLOG='' QB_CALLS=0
    if [ "$1" = message ]; then
        fv.views.message qr evBroadcast "$2" 99; rc=$?
        REPLY="rc=$rc res=$RESULT log=$QLOG"
    else
        fv.drivers.clearEvent
        FV_EV_WHAT=evBroadcast FV_EV_COMMAND=$2 FV_EV_INFO=99
        fv.views._virt qr HandleEvent
        REPLY="what=$FV_EV_WHAT info=$FV_EV_INFO log=$QLOG"
        fv.drivers.clearEvent
    fi
}
qcompare() {   # SEED -> QBAD += the differences, QSKIP += the handler calls saved
    local seed=$1 how c e a b na nb ca cb k
    local -A sb=() sg=()
    RANDOM=$seed QN=0 QL_EAT=()
    TQU.new qr 0 0 60 20
    qmk qr 0
    for how in message dispatch; do
        for c in cmA cmB cmB+ cmC cmSelectWindowNum cmZ; do
            # (cmB+: cmB with the built-in leaf handling it)
            QB_EAT='' e=${c%+}
            [[ $c == *+ ]] && QB_EAT=1
            FVQ_H=0
            qrun "$how" "$e"; a=$REPLY na=$FVQ_H ca=$QB_CALLS
            # (the full dispatch: the table emptied)
            sb=() sg=()
            for k in "${!__FV_VW_BCAST[@]}"; do sb[$k]=${__FV_VW_BCAST[$k]}; done
            for k in "${!__FV_VW_QGRP[@]}"; do sg[$k]=${__FV_VW_QGRP[$k]}; done
            __FV_VW_BCAST=() __FV_VW_QGRP=()
            FVQ_H=0
            qrun "$how" "$e"; b=$REPLY nb=$FVQ_H cb=$QB_CALLS
            for k in "${!sb[@]}"; do __FV_VW_BCAST[$k]=${sb[$k]}; done
            for k in "${!sg[@]}"; do __FV_VW_QGRP[$k]=${sg[$k]}; done
            if [[ $a != "$b" ]] || (( na > nb || ca > cb )); then
                QBAD+=" seed $seed $how $c: table [$a] ($na handler calls, $ca bodies) full [$b] ($nb, $cb);"
                qr.delete
                return
            fi
            QSKIP=$(( QSKIP + nb - na ))
        done
    done
    qr.delete
}
kt_test_start "random trees (seeded, 8 trees x 2 paths x 6 broadcasts): the table == a full dispatch (same reactions in order, each seeing its owner's Phase, same handler / rc), never more handler calls"
QBAD='' QSKIP=0
# (the built-in handler bodies counted, once for the whole test)
fvw_wrap FVQ_H fv.views._viewEvent fv.views._frameEvent fv.views._groupEvent fv.views._windowEvent fvq_gEvent fvq_bEvent
for s in 1 2 3 4 5 6 7 2026; do qcompare "$s"; [[ -n $QBAD ]] && break; done
fvw_unwrap fv.views._viewEvent fv.views._frameEvent fv.views._groupEvent fv.views._windowEvent fvq_gEvent fvq_bEvent
kt_test_log "# built-in handler calls the table saved over the full dispatch: $QSKIP"
if [[ -z $QBAD ]] && (( QSKIP > 0 )); then kt_test_pass "ok ($QSKIP handler calls saved)"; else kt_test_fail "${QBAD:0:2000} saved $QSKIP"; fi
unset QB_EAT

# ---- adding a row; overrides ------------------------------------------------------------
kt_test_start "adding a row: a built-in body without a row is called for every broadcast; with the row 'cmA' only for cmA (quiet for the rest); the row removed, every one again"
TGroup.new ng 0 0 20 5
TQN.new nn 0 0 3 1; listen nn; fv.views.insert ng nn
r=''
run3() { local c; QN_CALLS=0 QLOG=''; for c in cmA cmZ cmB; do fv.views.message ng evBroadcast "$c" || :; done; fv.views._quiet ng cmZ; r+="[$QN_CALLS $? $QLOG]"; }
run3
__FV_VW_BCAST[fvq_nEvent]='cmA'
run3
unset '__FV_VW_BCAST[fvq_nEvent]'
run3
ng.delete
want='[3 1 nn^cmA@phFocused;nn^cmZ@phFocused;nn^cmB@phFocused;][1 0 nn^cmA@phFocused;][3 1 nn^cmA@phFocused;nn^cmZ@phFocused;nn^cmB@phFocused;]'
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got $r want $want"; fi

kt_test_start "an override of a built-in body is always called (then its inherited body reacts as its row says); a subclass inheriting the body follows the row"
TGroup.new og 0 0 20 5
TQD.new od 0 0 3 1; listen od; fv.views.insert og od
TQE.new oe 4 0 7 1; listen oe; fv.views.insert og oe
QLOG='' QB_CALLS=0
for c in cmA cmZ; do fv.views.message og evBroadcast "$c" || :; done
fv.views._quiet og cmZ; q=$?
r="$QB_CALLS $q $QLOG"
og.delete
want='3 1 oe#cmA@phFocused;od~cmA@phFocused;od#cmA@phFocused;od~cmZ@phFocused;'
if [[ $r == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "got [$r] want [$want]"; fi

kt_test_start "the Phase stamp of a skipped group: after a broadcast no subview reacts to, a group whose dispatch skips a quiet subgroup (pr: the dispatch stamps it) and that subgroup (pg: the walk of fv.views._quiet stamps it, as the subgroup's own dispatch would before its quiet subgroup) hold the Phase a full dispatch leaves"
# (pgg, whose only subview is a quiet leaf, is not compared: a leaf the table
# skips is skipped without a call and without a stamp, as TView's handler for
# events other than a mouse-down; a Phase is read only by a handler called)
TQU.new pr 0 0 30 10
TView.new pl 0 0 3 1; listen pl; fv.views.insert pr pl
TGroup.new pg 0 2 20 8; fv.views.insert pr pg
TView.new pgl 0 0 3 1; listen pgl; fv.views.insert pg pgl
TGroup.new pgg 0 2 10 5; fv.views.insert pg pgg
TView.new pggl 0 0 3 1; listen pggl; fv.views.insert pgg pggl
pphase() {   # -> REPLY = the groups' Phases after a cmZ broadcast through pr, all at phPostProcess before
    local g
    for g in pr pg pgg; do local -n __q_g=${g}_data; __q_g[Phase]=phPostProcess; unset -n __q_g; done
    QLOG=''
    fv.views.message pr evBroadcast cmZ 0 || :
    REPLY="${pr_data[Phase]} ${pg_data[Phase]} $QLOG"
}
pphase; a=$REPLY
fv.views._quiet pg cmZ; q=$?
declare -A sb=() sg=()
for k in "${!__FV_VW_BCAST[@]}"; do sb[$k]=${__FV_VW_BCAST[$k]}; done
for k in "${!__FV_VW_QGRP[@]}"; do sg[$k]=${__FV_VW_QGRP[$k]}; done
__FV_VW_BCAST=() __FV_VW_QGRP=()
pphase; b=$REPLY
for k in "${!sb[@]}"; do __FV_VW_BCAST[$k]=${sb[$k]}; done
for k in "${!sg[@]}"; do __FV_VW_QGRP[$k]=${sg[$k]}; done
pr.delete
want='phFocused phFocused pr!cmZ@;'
if [[ $q == 0 && $a == "$want" && $b == "$want" ]]; then kt_test_pass "ok"; else kt_test_fail "quiet pg [$q]; table [$a] full [$b] want [$want]"; fi

# ---- the dialog scene ----------------------------------------------------------------------
kt_test_start "dialog scene (fvw_dscene): a Tab between the controls reaches a listening label-like leaf with both focus broadcasts, never a built-in leaf whose row lacks them"
fvw_dscene 80 24 4
TQL.new dlab 2 1 10 2; listen dlab; fv.views.insert dlg dlab
TQB.new dbi 12 1 20 2; listen dbi; fv.views.insert dlg dbi
fv.views.select dlgc1
fv.views.drawView app
QLOG='' QB_CALLS=0
fvw_count_on; FVW_CALLS=0
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbTab
fv.views._virt app HandleEvent
n=$FVW_CALLS
fvw_count_off
cur=${dlg_data[Current]}
r="$cur $QB_CALLS $QLOG"
fvw_undscene
want='dlgc2 0 dlab<cmReleasedFocus@phFocused;dlab<cmReceivedFocus@phFocused;'
kt_test_log "# calls dialog-tab $n"
if [[ $r == "$want" ]]; then kt_test_pass "ok ($n dispatches)"; else kt_test_fail "got [$r] want [$want]"; fi

kt_test_log "025_Quiet.sh completed"
