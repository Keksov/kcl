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
#     built-in leaf whose row lacks them;
#   * P3 3c, the hot-key map (10.3b): seeded random groups of built-in
#     bodies of this test with hot-key-only pre / post work (one Title, or
#     an _items array: __FV_VW_HKS), user pre / post views interleaved in Z
#     order, a focused widget and a disabled one, random Alt / plain / base
#     keys, Enter, a command, a direct Title write (h0 is a THB on purpose)
#     and a focus change mid-way: the map gives the same reactions, with the
#     owner's Phase each saw and the Phase left after each event, as a full
#     scan (the table emptied), never more widget calls.

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

# ---- P3 stage 3b: the list's row and the direct list -> bar link (P3-4, L7) -------------
kt_test_start "3b rows: TScrollBar none, TListViewer cmScrollBarChanged cmScrollBarClicked"
r="[${__FV_VW_BCAST[fv.views._sbEvent]-x}][${__FV_VW_BCAST[fv.views._lvEvent]-x}]"
if [[ $r == '[][cmScrollBarChanged cmScrollBarClicked]' ]]; then kt_test_pass "ok"; else kt_test_fail "got [$r]"; fi

kt_test_start "3b: a list moving its own bar: the bar's cmScrollBarChanged is not delivered when the list is its only listener (no walk, no dispatch), and the window is quiet for it then (for that bar only)"
fvw_lscene 80 24
fv.views.drawView app
QX_N=0
src=$(declare -f fv.views._lvBcast)
eval "__q_${src}"
fv.views._lvBcast() { QX_N=$(( QX_N + 1 )); __q_fv.views._lvBcast "$@"; }
fvw_count_on; FVW_CALLS=0
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbPgDn; fv.views._virt app HandleEvent
n=$FVW_CALLS
fvw_count_off
fv.views._quiet w2 cmScrollBarChanged; a=$?
__FV_VW_QX=w2l; fv.views._quiet w2 cmScrollBarChanged w2__fvsb1; b=$?
# (exact: only the list's own vertical bar; another bar's broadcast still reaches it)
fv.views._quiet w2 cmScrollBarChanged w2__fvsbX; b+=$?; __FV_VW_QX=''
fv.views._quiet w2 cmScrollBarClicked; c=$?
if [[ $QX_N == 0 && $n == 2 && "$a$b$c" == 1011 && ${w2l_data[TopItem]} == "${w2__fvsb1_data[Value]}" ]]; then kt_test_pass "ok"; else kt_test_fail "list told $QX_N times, $n dispatches, quiet $a$b$c"; fi

kt_test_start "3b: another listener in the window gets the broadcast, the list still does not; the bar moved by its own mouse reaches the list (FV)"
TQL.new qlis 0 0 1 1; listen qlis; fv.views.insert w2 qlis
QLOG='' QX_N=0
fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=kbPgDn; fv.views._virt app HandleEvent
a="$QX_N $QLOG"
QLOG='' QX_N=0
fv.drivers.clearEvent; FV_EV_WHAT=evMouseWheel FV_EV_MOUSE_X=79 FV_EV_MOUSE_Y=10 FV_EV_WHEEL=2; fv.views._virt app HandleEvent
b="$QX_N" t=${w2l_data[TopItem]} v=${w2__fvsb1_data[Value]}
eval "$src"
fvw_unlscene
if [[ $a == '0 qlis<cmScrollBarChanged@phFocused;' && $b == 2 && $t == "$v" && $t == 23 ]]; then kt_test_pass "ok"; else kt_test_fail "[$a] [$b] top $t bar $v"; fi


# ---- P3 stage 3c: the hot-key map (design §3.1, 10.3b) ----------------------------
kt_test_section "025: the hot-key map (P3 10.3b)"
# a built-in body of this test with hot-key-only pre / post work, like
# fv.dialogs' TButton (one text: Title) and TCluster (an array: _items): Alt
# + a hot letter in any phase, the plain letter in phPostProcess, Space /
# Enter while focused; registered in __FV_VW_IMPL and __FV_VW_HKS. Each call
# is counted per view; a reaction is noted with the owner's Phase
declare -A HKN=()
HKLOG=''
fvh_note() {
    local -n __h_d=${1}_data
    local -n __h_o=${__h_d[Owner]}_data
    HKLOG+="$1$2:${__h_o[Phase]}:$FV_EV_KEY$FV_EV_CHAR;"
}
fvh_event() {
    HKN[$1]=$(( ${HKN[$1]:-0} + 1 ))
    [ "$FV_EV_WHAT" = evKeyDown ] || return 0
    local -n __h_d=${1}_data
    local -n __h_o=${__h_d[Owner]}_data
    local p=0 t c
    local -a tt=()
    if [ "${__h_o[Phase]}" = phPostProcess ]; then p=1; fi
    if [[ -n ${__h_d[Title]+x} ]]; then tt=("${__h_d[Title]}"); else local -n __h_i=${1}_items; tt=("${__h_i[@]}"); fi
    for t in "${tt[@]}"; do
        c=${t#*'~'}; [ "$c" = "$t" ] && continue; c=${c:0:1}
        if fv.views._hk "$c" "$p" "$1"; then fvh_note "$1" "!$c"; fv.views.clearEvent "$1"; return 0; fi
    done
    if (( ${__h_d[State]:-0} & FV_SF_FOCUSED )) && [ "$FV_EV_KEY" = kbEnter ]; then fvh_note "$1" '!enter'; fv.views.clearEvent "$1"; fi
}
class THB : TView
    public
        var Title
        nofields override proc HandleEvent
end
THB.HandleEvent() { fvh_eventB "$this" "$@" || return; }
build THB
class THM : TView
    public
        nofields override proc HandleEvent
end
THM.HandleEvent() { fvh_eventM "$this" "$@" || return; }
build THM
fvh_eventB() { fvh_event "$@"; }
fvh_eventM() { fvh_event "$@"; }
__FV_VW_IMPL[THB.HandleEvent]=fvh_eventB __FV_VW_IMPL[THM.HandleEvent]=fvh_eventM
# a user view with pre / post work: notes every key; handles kbF5 (one of them)
declare -A HU_EAT=()
class THU : TView
    public
        override proc HandleEvent
end
THU.HandleEvent() {
    if [ "$FV_EV_WHAT" = evKeyDown ]; then
        fvh_note "$this" '<'
        if [ "${HU_EAT[$this]-}" = "$FV_EV_KEY" ]; then fv.views.clearEvent "$this"; fi
    fi
}
build THU
hk_on() {
    if (( $1 )); then __FV_VW_HKS[fvh_eventB]='_data[Title]' __FV_VW_HKS[fvh_eventM]='_items[@]'
    else unset '__FV_VW_HKS[fvh_eventB]' '__FV_VW_HKS[fvh_eventM]'; fi
    fv.views._hkDirty
}
# the letters: Latin titles from LAT, Cyrillic ones from CYR (never typed
# with a base key; as plain letters their layout bases, s and z, are no
# title's: ы is on the US s key, я on z), Cyrillic keys with a base key from
# CYK (no title has them): so a typed match and a base match never compete
# (where they do, the map lets the typed one win by design: fv.dialogs'
# 018 tests the passes)
LAT=(a b c d e) CYR=(ы я) CYK=(ж э)
hmk() {   # N random views into hr
    local i k v t
    for (( i = 0; i < $1; i++ )); do
        # (h0 a THB on purpose: the direct Title write at event 6 always lands)
        v=h$i k=$(( RANDOM % 6 ))
        if (( i == 0 )); then k=0; fi
        case $k in
            0|1) THB.new "$v" 0 0 3 1
                 if (( RANDOM % 4 )); then t=${LAT[RANDOM % 5]}; else t=${CYR[RANDOM % 2]}; fi
                 printf -v "${v}_data[Title]" '%s' "x~$t~y" ;;
            2) THM.new "$v" 0 0 3 1; declare -ga "${v}_items=(\"~${LAT[RANDOM % 5]}~1\" \"~${LAT[RANDOM % 5]}~2\" \"z\")" ;;
            3|4) THU.new "$v" 0 0 3 1; (( RANDOM % 4 )) || HU_EAT[$v]=kbF5 ;;
            5) TView.new "$v" 0 0 3 1 ;;
        esac
        local -n __h_n=${v}_data
        case $k in
            0|1|2) __h_n[Options]=$(( FV_OF_SELECTABLE | FV_OF_PREPROCESS | FV_OF_POSTPROCESS )) ;;
            3|4) __h_n[Options]=$(( (RANDOM % 3 + 1) << 4 )) ;;
            5) __h_n[Options]=$FV_OF_SELECTABLE ;;
        esac
        if (( k == 2 )) && (( RANDOM % 5 == 0 )); then __h_n[State]=$(( __h_n[State] | FV_SF_DISABLED )); fi
        unset -n __h_n
        fv.views.insert hr "$v"
    done
}
# hkeys: one random event into FV_EV_*
hkey() {
    local r=$(( RANDOM % 9 ))
    fv.drivers.clearEvent
    FV_EV_WHAT=evKeyDown FV_EV_BASE=''
    case $r in
        0|1) FV_EV_CHAR=${LAT[RANDOM % 5]} FV_EV_KEY=kbAlt${FV_EV_CHAR^^} ;;
        2) FV_EV_CHAR=${LAT[RANDOM % 5]} FV_EV_KEY=kbChar ;;
        3) FV_EV_CHAR=${CYR[RANDOM % 2]} FV_EV_KEY=kbAltQ FV_EV_BASE=q ;;
        4) FV_EV_CHAR=${CYK[RANDOM % 2]} FV_EV_BASE=${LAT[RANDOM % 5]} FV_EV_KEY=kbAlt${FV_EV_BASE^^} ;;
        5) FV_EV_CHAR=${CYR[RANDOM % 2]} FV_EV_KEY=kbChar ;;
        6) FV_EV_KEY=kbF5 ;;
        7) FV_EV_KEY=kbEnter ;;
        8) FV_EV_WHAT=evCommand FV_EV_COMMAND=cmZz ;;
    esac
}
# hplay SEED MAP -> REPLY = the log of 12 events (the reactions, the outcome);
# HCALLS = the built-in bodies' calls. A direct Title write mid-way, and a
# focus change
hplay() {
    local e out='' t
    RANDOM=$1 HKN=() HU_EAT=()
    hk_on "$2"
    TGroup.new hr 0 0 60 20
    hmk $(( 4 + RANDOM % 6 ))
    hr_data[State]=$(( hr_data[State] | FV_SF_SELECTED | FV_SF_MODAL ))
    fv.views.setState hr "$FV_SF_FOCUSED" 1
    for (( e = 0; e < 12; e++ )); do
        if (( e == 6 )); then h0_data[Title]="~${LAT[RANDOM % 5]}~w"; fi
        if (( e == 8 )); then fv.views.focusNext hr 0 || :; fi
        HKLOG=''
        hkey
        fv.views._virt hr HandleEvent
        out+="[$e $FV_EV_WHAT ${hr_data[Phase]-} $HKLOG]"
    done
    REPLY=$out HCALLS=0
    for t in "${HKN[@]}"; do HCALLS=$(( HCALLS + t )); done
    hr.delete
    fv.drivers.clearEvent
}
kt_test_start "the map == a full scan: 40 seeded random groups, 12 events each (Alt / plain / base keys, user pre / post views interleaved, a focused widget, a disabled one, a direct Title write): the same reactions with their Phases, never more widget calls"
bad='' saved=0
for (( s = 1; s <= 40; s++ )); do
    hplay "$s" 1; a=$REPLY ca=$HCALLS
    hplay "$s" 0; b=$REPLY cb=$HCALLS
    if [[ $a != "$b" ]] || (( ca > cb )); then bad+=" seed $s: map [$a] calls $ca vs full [$b] calls $cb;"; fi
    saved=$(( saved + cb - ca ))
done
hk_on 0
if [[ -z $bad ]] && (( saved > 0 )); then kt_test_pass "$saved widget calls saved"; else kt_test_fail "${bad:0:2000} saved $saved"; fi

kt_test_log "025_Quiet.sh completed"
