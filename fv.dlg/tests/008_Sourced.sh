#!/usr/bin/env bash
# 008_Sourced.sh - the bash face (design §2.2, P4-2):
#   * fv.dlg.run alone: RESULT, FV_DLG_TAGS, FV_DLG_CMD, the status; nothing
#     printed unless --stdout / --output-fd asks;
#   * a session (fv.dlg.begin / fv.dlg.end): one application for several
#     dialogs (the same FV_APP, the desktop and the background title painted
#     by begin, a run's --backtitle replaces its text), each dialog gone
#     after its run; on a terminal (fv.video stubbed, a subshell) one
#     initVideo / doneVideo for the whole session against one per plain
#     call; an infobox in a session returns at once (no event read), stays
#     on the desktop until the next run; end puts the caller's terminal
#     settings back and closes the session's files; the refusals (a second
#     begin, a dialog option to begin, a terminal option to run inside the
#     session, a call inside $( ) of the session's shell) — 255 and one
#     line; end without a session: nothing, 0;
#   * inside a running fv application (the host: fv.app's TApplication with
#     its windows and status line): fv.dlg.run uses its desktop (the
#     host's application stays, its palette untouched by NO_COLOR, no
#     background title), the minimum against the host's desktop, a terminal
#     option refused, an infobox left until fv.dlg.end — not selectable:
#     the host's current window and its State unchanged (M1; in a session
#     not the desktop's current view either); begin leaves RESULT '' (L4);
#   * $( fv.dlg.run --stdout ... ) without a session: the subshell makes its
#     own application, the answer captured; a session inside a subshell.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvdlg_testlib.sh"
fvdl_init "$(basename "$0" .sh)" "$@"

# ev SPEC... — the scripted terminal for the next calls (no --fv-headless:
# the session's or the host's)
ev() { fvdl_events "$@"; }
noev() { fva_noevents; __FV_VW_EOF=0; }
# nodlg — rc 0 when no fv.dlg dialog is alive on the desktop
nodlg() { [[ -z ${FV_DESKTOP-} || ( -z ${__FV_VW_LIVE[${FV_DESKTOP}__fvdlg]-} && -z ${__FV_VW_LIVE[${FV_DESKTOP}__fvdlg2]-} ) ]]; }
# dcur — the desktop's current view (printed)
dcur() { local -n __t_d=${FV_DESKTOP}_data; printf '%s' "${__t_d[Current]-}"; }

kt_test_section "008: fv.dlg.run alone"
fvdl_run 'key kbDown' 'key kbEnter' -- --menu 'Pick' 0 0 0 a A b B > "$FVW_TMP/out1"
kt_test_start "a menu: RESULT the tag, FV_DLG_TAGS (one), FV_DLG_CMD cmOK, rc 0; nothing on stdout"
if [[ $FVDL_RC == 0 && $FVDL_RES == b && ${FV_DLG_TAGS[*]} == b && ${#FV_DLG_TAGS[@]} == 1 && $FVDL_CMD == cmOK && ! -s $FVW_TMP/out1 ]]; then kt_test_pass ok
else kt_test_fail "rc $FVDL_RC [$FVDL_RES] [${FV_DLG_TAGS[*]}] $FVDL_CMD [$(<"$FVW_TMP/out1")]"; fi
fvdl_run 'key kbEnter' -- --output-fd 1 --checklist 'Chk' 0 0 0 'a b' A on c C on > "$FVW_TMP/out1"
kt_test_start "--output-fd 1: the answer printed as well (no newline), RESULT the same"
if [[ $FVDL_RC == 0 && $FVDL_RES == '"a b" "c"' && $(<"$FVW_TMP/out1") == '"a b" "c"' && $(( $(wc -c < "$FVW_TMP/out1") )) == 9 ]]; then kt_test_pass ok
else kt_test_fail "rc $FVDL_RC [$FVDL_RES] [$(<"$FVW_TMP/out1")]"; fi

kt_test_section "008: a session"
w0=$FV_SCREEN_W h0=$FV_SCREEN_H hl0=${FV_APP_HEADLESS-unset} k0=$FV_KEY_FD
RESULT=keep
fv.dlg.begin --fv-headless --fv-size 70x20 --backtitle 'Setup'; r=$?
rb=$RESULT
app=$FV_APP
fvdl_snap; fvdl_row 0; t0=$REPLY; fvdl_row 1; d1=$REPLY
kt_test_start "begin: rc 0, RESULT '' (no internal view name: L4), the session's application, the desktop and the background title painted at once (70 x 20)"
if [[ $r == 0 && -z $rb && -n $app && -n ${__FV_VW_LIVE[$app]-} && $t0 == ' Setup '* && $d1 == '░░░'* && $FV_SCREEN_W == 70 && ${#t0} == 70 ]]; then kt_test_pass "$app"
else kt_test_fail "rc $r app [$app] [$t0] [$d1] W $FV_SCREEN_W"; fi
ev 'char x' 'key kbEnter'
fv.dlg.run --inputbox 'Host:' 0 0 localhost; r1=$? res1=$RESULT
ev 'char _' 'key kbEnter'
fv.dlg.run --checklist 'Pkgs' 0 0 0 git Git off vim Vim on; r2=$? res2=$RESULT tags2=("${FV_DLG_TAGS[@]}")
ev 'key kbTab' 'key kbEnter'
fv.dlg.run --yesno 'Sure?' 0 0; r3=$?
noev
kt_test_start "three runs in the session: their answers; the same application after each; no dialog left"
if [[ $r1 == 0 && $res1 == x && $r2 == 0 && $res2 == '"git" "vim"' && ${tags2[*]} == 'git vim' && $r3 == 1 && $FV_APP == "$app" && -n ${__FV_VW_LIVE[$app]-} ]] && nodlg; then kt_test_pass ok
else kt_test_fail "[$r1 $res1] [$r2 $res2 ${tags2[*]}] [$r3] app [$FV_APP]"; fi
ev 'run fvdl_snap' 'key kbEnter'
fv.dlg.run --backtitle 'Step 2' --msgbox 'hi' 0 0
noev
fvdl_row 0; t2=$REPLY
fvdl_box; b=$REPLY
kt_test_start "a run's --backtitle replaces the session's text; the box below it, centred on 70 x 20"
if [[ $t2 == ' Step 2 '* && $b == '27 7 43 13' ]]; then kt_test_pass "$b"; else kt_test_fail "[$t2] [$b]"; fi
ev 'key kbEnter'
cur0=$(dcur)
fv.dlg.run --infobox 'Please wait' 0 0; r=$?
n=$FVA_N
noev
cur1=$(dcur)
fvdl_snap; fvdl_find 'Please wait'; p=$REPLY
kt_test_start "an infobox in the session: rc 0 at once (no event read), drawn on the desktop, still there, not the desktop's current view (M1)"
if [[ $r == 0 && $n == 0 && -n $p && $cur1 == "$cur0" ]] && ! nodlg; then kt_test_pass "$p"; else kt_test_fail "rc $r events $n [$p] current [$cur0] -> [$cur1]"; fi
ev 'run fvdl_snap' 'key kbEnter'
fv.dlg.run --topleft --msgbox 'next' 0 0; r=$?
noev
fvdl_find 'Please wait'; p=$REPLY
kt_test_start "the next run removes the infobox first"
if [[ $r == 0 && -z $p ]] && nodlg; then kt_test_pass ok; else kt_test_fail "rc $r [$p]"; fi
x=$(fv.dlg.run --msgbox hi 0 0 2>&1); r=$?
kt_test_start "\$( fv.dlg.run ) in the session's shell: refused, 255, one line"
if [[ $r == 255 && $x == 'fv.dlg.run: refused in a subshell ('*'call it in the shell that owns the screen, the answer is in RESULT' ]]; then kt_test_pass ok; else kt_test_fail "rc $r [$x]"; fi
fv.dlg.run --fv-headless --msgbox hi 0 0 2>"$FVW_TMP/e"; r=$?
kt_test_start "a terminal option inside the session: refused"
if [[ $r == 255 && $(<"$FVW_TMP/e") == 'fv.dlg.run: --fv-headless belongs to fv.dlg.begin (a session is running)' ]]; then kt_test_pass ok; else kt_test_fail "rc $r [$(<"$FVW_TMP/e")]"; fi
fv.dlg.begin --fv-headless 2>"$FVW_TMP/e"; r=$?
kt_test_start "a second begin: refused, the session unchanged"
if [[ $r == 255 && $(<"$FVW_TMP/e") == 'fv.dlg.begin: a session is already running (fv.dlg.end first)' && $FV_APP == "$app" ]]; then kt_test_pass ok; else kt_test_fail "rc $r [$(<"$FVW_TMP/e")]"; fi
kfd=${__FV_DL_SES[kfd]-}
fv.dlg.end; r=$?
kt_test_start "end: rc 0, the application gone, the caller's settings back, the key file closed"
if [[ $r == 0 && -z $FV_APP && -z ${__FV_VW_LIVE[$app]-} && $FV_SCREEN_W == "$w0" && $FV_SCREEN_H == "$h0" && ${FV_APP_HEADLESS-unset} == "$hl0" && $FV_KEY_FD == "$k0" && -n $kfd ]] \
      && ! { : <&"$kfd"; } 2>/dev/null; then kt_test_pass ok
else kt_test_fail "rc $r app [$FV_APP] W $FV_SCREEN_W H $FV_SCREEN_H hl ${FV_APP_HEADLESS-unset} key $FV_KEY_FD/$k0 kfd [$kfd]"; fi
fv.dlg.end; r=$?
kt_test_start "end without a session: nothing, rc 0"
if [[ $r == 0 ]]; then kt_test_pass ok; else kt_test_fail "rc $r"; fi
fv.dlg.begin --title T 2>"$FVW_TMP/e"; r=$?
kt_test_start "begin with a dialog's option: refused, no application"
if [[ $r == 255 && $(<"$FVW_TMP/e") == "fv.dlg.begin: 'title' is a dialog's option, not the session's (give it to fv.dlg.run)" && -z $FV_APP ]]; then kt_test_pass ok
else kt_test_fail "rc $r [$(<"$FVW_TMP/e")] [$FV_APP]"; fi
fv.dlg.begin --msgbox x 0 0 2>"$FVW_TMP/e"; r=$?
kt_test_start "begin with a widget: refused"
if [[ $r == 255 && $(<"$FVW_TMP/e") == "fv.dlg.begin: one widget per call ('--msgbox' after '--infobox'); --and-widget is not supported" ]]; then kt_test_pass ok
else kt_test_fail "rc $r [$(<"$FVW_TMP/e")]"; fi

kt_test_section "008: one terminal start per session (fv.video stubbed)"
termstub() {   # MODE -> "init/done counts|answers"
    (
        REC='' ANS=''
        fv.video.initVideo() { REC+='i'; FV_VIDEO_ON=1; return 0; }
        fv.video.doneVideo() { REC+='d'; FV_VIDEO_ON=0; return 0; }
        fv.drivers.initEvents() { return 0; }
        fv.drivers.doneEvents() { return 0; }
        exec {o}>"$FVW_TMP/term.out"
        FV_VIDEO_OUT_FD=$o FV_SCREEN_W=80 FV_SCREEN_H=24 FV_VIDEO_ON=0
        unset FV_APP_HEADLESS
        if [ "$1" = session ]; then fv.dlg.begin; fi
        for t in a b c; do
            fvdl_events 'key kbEnter'
            fv.dlg.run --menu 'Pick' 0 0 0 "$t" X; ANS+="$?$RESULT "
            fva_noevents; __FV_VW_EOF=0
        done
        if [ "$1" = session ]; then fv.dlg.end; fi
        printf '%s|%s' "$REC" "$ANS"
    )
}
out=$(termstub plain)
kt_test_start "three plain calls: three initVideo / doneVideo pairs"
if [[ $out == 'ididid|0a 0b 0c ' ]]; then kt_test_pass "$out"; else kt_test_fail "$out"; fi
out=$(termstub session)
kt_test_start "the same in a session: one initVideo (begin) and one doneVideo (end)"
if [[ $out == 'id|0a 0b 0c ' ]]; then kt_test_pass "$out"; else kt_test_fail "$out"; fi

kt_test_section "008: inside a running fv application (the host)"
hb() { fva_b "${FV_DESKTOP}__fvdlg"; HB=$REPLY; }
hoststub() {   # -> a line of facts
    (
        fva_app 80 24
        fva_paint
        pal0=$__FV_VW_APAL
        fvdl_events 'run fvdl_snap' 'run hb' 'key kbDown' 'key kbEnter'
        NO_COLOR=1 fv.dlg.run --backtitle B --menu 'Pick' 0 0 0 a A b B; r1=$? res1=$RESULT
        fva_noevents; __FV_VW_EOF=0
        b1=$HB
        fvdl_find 'Panel two'; p=$REPLY
        bt=${__FV_VW_LIVE[${FV_DESKTOP}__fvbacktitle]-}
        fv.dlg.run --fv-mouse off --msgbox x 0 0 2>"$FVW_TMP/he"; r2=$?
        fv.dlg.run --infobox 'Working' 0 0; r3=$?
        i1=${__FV_VW_LIVE[${FV_DESKTOP}__fvdlg]-}
        fv.dlg.end
        i2=${__FV_VW_LIVE[${FV_DESKTOP}__fvdlg]-}
        printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s' "$r1" "$res1" "$b1" "${p:+host}" "${bt:-nobt}" "$FV_APP" \
            "$([[ $__FV_VW_APAL == "$pal0" ]] && echo samepal)" "$r2" "$(<"$FVW_TMP/he")" "$r3" "${i1:+info}" "${i2:-gone}"
        fva_unapp
    )
}
out=$(hoststub)
kt_test_start "the host's desktop (its windows behind, the status line's row taken off), the answer; FV_APP the host's; NO_COLOR and --backtitle leave the host alone; a terminal option refused; an infobox left until fv.dlg.end"
want="0|b|27 7 53 16|host|nobt|app|samepal|255|fv.dlg.run: --fv-mouse belongs to the running fv application|0|info|gone"
if [[ $out == "$want" ]]; then kt_test_pass ok; else kt_test_fail "got [$out] want [$want]"; fi
hostsmall() {
    (
        fva_app 30 8
        fva_paint
        fv.dlg.run --menu 'Pick' 0 0 0 a A 2>"$FVW_TMP/he"; r=$?
        printf '%s|%s' "$r" "$(<"$FVW_TMP/he")"
        fva_unapp
    )
}
hostinfo() {
    (
        fva_app 80 24
        fva_paint
        c0=$(dcur) s0=${w2_data[State]-}
        fv.dlg.run --infobox 'Working' 0 0; r=$?
        c1=$(dcur) s1=${w2_data[State]-}
        fvdl_snap; fvdl_find 'Working'; p=$REPLY
        fv.dlg.end
        printf '%s|%s|%s|%s|%s|%s' "$r" "$c0" "$c1" "$s0" "$s1" "${p:+shown}"
        fva_unapp
    )
}
out=$(hostinfo)
IFS='|' read -r r c0 c1 s0 s1 p <<< "$out"
kt_test_start "an infobox in the host: shown, the host's current window and its State unchanged (M1: not selectable)"
if [[ $r == 0 && $c0 == w2 && $c1 == "$c0" && -n $s0 && $s1 == "$s0" && $p == shown ]]; then kt_test_pass "$out"; else kt_test_fail "$out"; fi
out=$(hostsmall)
kt_test_start "the minimum against the host's desktop (30 x 8 minus the status line)"
if [[ $out == '255|fv.dlg.run: the desktop is too small (need 26x8, have 30x7)' ]]; then kt_test_pass ok; else kt_test_fail "$out"; fi

kt_test_section "008: \$( ) and subshells"
fvdl_events 'key kbDown' 'key kbEnter'
RESULT=keep
x=$(fv.dlg.run --fv-headless --stdout --menu 'Pick' 0 0 0 a A b B); r=$?
fva_noevents; __FV_VW_EOF=0
kt_test_start "\$( fv.dlg.run --stdout ) without a session: the subshell's own application, the answer captured; the caller's RESULT untouched"
if [[ $r == 0 && $x == b && $RESULT == keep && -z $FV_APP ]]; then kt_test_pass ok; else kt_test_fail "rc $r [$x] [$RESULT] [$FV_APP]"; fi
x=$(
    fv.dlg.begin --fv-headless
    fvdl_events 'key kbEnter'
    fv.dlg.run --menu 'Pick' 0 0 0 a A; printf '%s:%s;' "$?" "$RESULT"
    fvdl_events 'key kbEnter'
    fv.dlg.run --menu 'Pick' 0 0 0 z Z; printf '%s:%s;' "$?" "$RESULT"
    fv.dlg.end
    printf '%s' "${FV_APP:-none}"
)
kt_test_start "a session inside a subshell: its own, ended there; nothing in the caller"
if [[ $x == '0:a;0:z;none' && -z $FV_APP && -z ${__FV_DL_SES[app]-} ]]; then kt_test_pass ok; else kt_test_fail "[$x]"; fi

kt_test_log "008_Sourced.sh completed"
