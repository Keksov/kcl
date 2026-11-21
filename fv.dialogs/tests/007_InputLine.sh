#!/usr/bin/env bash
# 007_InputLine.sh - TInputLine (FV dialogs.inc, FPC 2025; design P3 §4):
#   * the constructor (fields, options, the refusal), the look: colours 1 / 2
#     / 5, `<` and `>` in colour 4, the selection in colour 3, the cursor;
#   * editing and selection against a model: seeded random key sequences
#     (characters of ASCII, Cyrillic, CJK and emoji — each one cluster, the
#     wide ones two cells — Left Right Home End, Shift + those, Ctrl+Left /
#     Ctrl+Right, Back, Del, Ins (overwrite), Ctrl+Y) over a 20-cell line
#     with MaxLen 30; after every key the text, CurPos FirstPos SelStart
#     SelEnd, the cursor and the row's cells and colours equal the model's
#     (FV's rules in clusters: FirstPos keeps CurPos within SizeX - 3 cells,
#     a wide cluster never straddles the right edge), now and then == a full
#     repaint;
#   * FV's rules one by one: FirstPos = SizeX - 3, MaxLen, overwrite with
#     MaxLen, Ctrl+Y, the WordStar keys, keys it does not take pass, the
#     overwrite cursor (sfCursorIns: fv.video type 2, block), P3-12 (a cursor
#     move inside the text draws nothing, one write per typed character);
#   * password mode (D29): one PasswordChar cell per cluster (a wide one
#     too), the selection colour, the cursor after the masked clusters,
#     getText the real text;
#   * SelectAll on focus (Tab in), getText / setText / selectAll, Valid with
#     a Validator function, refusals.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "007: TInputLine"

# the scene: a modeless dialog with a 20-cell input line (MaxLen 30) at
# dialog (3, 2) -> screen (13, 6), a button after it
scene() {
    fvw_tscene 80 24
    TDialog.new dlg 10 4 70 18 'Edit'
    TInputLine.new il 3 2 23 3 "${1:-30}"
    TButton.new ok 14 10 24 12 'O~K~' cmOK "$FV_BF_DEFAULT"
    fv.views.insert dlg il; fv.views.insert dlg ok
    fv.views.select il
    fv.views.insert desk dlg; fv.views.select dlg
    fv.views.drawView app
}
unscene() { app.delete; if fv.views.isView dlg; then dlg.delete; fi; }
k() { fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=$1 FV_EV_CHAR=${2-} FV_EV_BASE=''; fv.views._virt dlg HandleEvent; }
X0=13 Y0=6 SX=20

kt_test_section "007: the constructor and the look"
scene
kt_test_start "the fields and options (FV Init): MaxLen, all positions 0, sfCursorVis, ofSelectable + ofFirstClick, no password, no validator"
s=${il_data[State]} o=${il_data[Options]}
if [[ ${il_data[MaxLen]} == 30 && ${il_data[CurPos]}${il_data[FirstPos]}${il_data[SelStart]}${il_data[SelEnd]} == 0000 && -z ${il_data[PasswordChar]} && -z ${il_data[Validator]} ]] \
   && (( (s & FV_SF_CURSORVIS) && (o & FV_OF_SELECTABLE) && (o & FV_OF_FIRSTCLICK) )) && (( ${#il_cl[@]} == 0 )); then kt_test_pass ok
else kt_test_fail "maxlen ${il_data[MaxLen]} state $s options $o"; fi
kt_test_start "refused before anything is made: no MAXLEN, MAXLEN not digits (rc 2, one Error line)"
r1=0; VERBOSE_KKLASS=quiet TInputLine.new bad1 0 0 10 1 2>/dev/null || r1=$?
r2=0; err=$(TInputLine.new bad2 0 0 10 1 x2 2>&1) || r2=$?
if [[ $r1 == 2 && $r2 == 2 && $err == *'Error: fv.dialogs: TInputLine.Create'*'MAXLEN digits'* ]] && ! fv.views.isView bad1; then kt_test_pass ok; else kt_test_fail "$r1 $r2 [$err]"; fi
for v in bad1 bad2; do declare -F "$v.delete" >/dev/null && "$v.delete" 2>/dev/null; done
fv.views.getColor il 1; C1=$RESULT; fv.views.getColor il 2; C2=$RESULT; fv.views.getColor il 3; C3=$RESULT
fv.views.getColor il 4; C4=$RESULT; fv.views.getColor il 5; C5=$RESULT
kt_test_start "an empty focused line: blanks in colour 2 (focused), the cursor at cell 1"
fvg_cells $X0 $Y0 $SX
fvw_rep() { REPLY=''; local i; for (( i = 0; i < $2; i++ )); do REPLY+=$1; done; }
fvw_rep "$C2" $SX
if [[ $RESULT == "                    " && ${REPLY} == "$(fvg_cells $X0 $Y0 $SX; printf '%s' "$REPLY")" ]]; then :; fi
fvg_cells $X0 $Y0 $SX; got=$REPLY; fvw_rep "$C2" $SX
if [[ $RESULT == "                    " && $got == "$REPLY" && ${il_data[CursorX]} == 1 ]]; then kt_test_pass ok; else kt_test_fail "[$RESULT] [$got] cx ${il_data[CursorX]}"; fi
kt_test_start "typed text drawn from cell 1; unfocused (focus on the button): colour 1, no '<'"
for ch in a b c; do k kbChar "$ch"; done
fv.views.focus ok
fvg_cells $X0 $Y0 5; a="$RESULT|${REPLY:0:4}"
fv.views.focus il
if [[ $a == " abc |$C1$C1$C1$C1" ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$a] $FVW_DIFF"; fi
kt_test_start "not selectable: colour 5"
il_data[Options]=$(( il_data[Options] & ~FV_OF_SELECTABLE )); fv.views.drawView il
fvg_cells $X0 $Y0 3; a=$REPLY
il_data[Options]=$(( il_data[Options] | FV_OF_SELECTABLE )); fv.views.drawView il
if [[ $a == "$C5$C5$C5" ]]; then kt_test_pass ok; else kt_test_fail "[$a]"; fi
unscene

# ---- the model --------------------------------------------------------------------------
# M_T / M_W the clusters and their cells; M_C M_F M_S M_E CurPos FirstPos
# SelStart SelEnd; M_I overwrite; M_MAX MaxLen; SX the width
m_cells() {   # A B -> REPLY
    local i n=0
    for (( i = $1; i < $2; i++ )); do n=$(( n + M_W[i] )); done
    REPLY=$n
}
m_dl() { [[ $1 == ' ' || $1 == . ]]; }   # (the alphabet's delimiters, FPC's set)
m_del() {     # A B
    M_T=("${M_T[@]:0:$1}" "${M_T[@]:$2}"); M_W=("${M_W[@]:0:$1}" "${M_W[@]:$2}"); M_C=$1
}
m_key() {     # KEY [UNIT WIDTH]
    local key=$1 x=0 an=0 i len
    case $key in kbShift*|kbCtrlShift*) x=1; key=${key/Shift/}; if (( M_C == M_E )); then an=$M_S; else an=$M_E; fi ;; esac
    len=${#M_T[@]}
    case $key in
        kbLeft) (( M_C > 0 )) && M_C=$(( M_C - 1 )) ;;
        kbRight) (( M_C < len )) && M_C=$(( M_C + 1 )) ;;
        kbHome) M_C=0 ;;
        kbEnd) M_C=$len ;;
        kbCtrlLeft)
            if (( M_C > 0 )); then
                i=1; while (( i <= len )) && m_dl "${M_T[i-1]}"; do i=$(( i + 1 )); done
                if (( M_C == i - 1 )); then M_C=0
                else
                    i=$M_C
                    while (( i > 0 )) && m_dl "${M_T[i-1]}"; do i=$(( i - 1 )); done
                    while (( i > 0 )) && ! m_dl "${M_T[i-1]}"; do i=$(( i - 1 )); done
                    M_C=$i
                fi
            fi ;;
        kbCtrlRight)
            i=$len; while (( i > 0 )) && m_dl "${M_T[i-1]}"; do i=$(( i - 1 )); done
            if (( M_C == i )); then M_C=$len
            else
                i=$M_C
                while (( i < len )) && m_dl "${M_T[i]}"; do i=$(( i + 1 )); done
                while (( i < len )) && ! m_dl "${M_T[i]}"; do i=$(( i + 1 )); done
                M_C=$i
            fi ;;
        kbBack) if (( M_S == M_E && M_C > 0 )); then M_S=$(( M_C - 1 )) M_E=$M_C; fi; if (( M_S < M_E )); then m_del "$M_S" "$M_E"; fi ;;
        kbDel) if (( M_S == M_E && M_C < len )); then M_S=$M_C M_E=$(( M_C + 1 )); fi; if (( M_S < M_E )); then m_del "$M_S" "$M_E"; fi ;;
        kbIns) M_I=$(( ! M_I )) ;;
        kbCtrlY) M_T=() M_W=() M_C=0 ;;
        kbChar)
            if (( M_I )); then (( M_C < len )) && m_del "$M_C" "$(( M_C + 1 ))"
            elif (( M_S < M_E )); then m_del "$M_S" "$M_E"; fi
            if (( ${#M_T[@]} < M_MAX )); then
                M_T=("${M_T[@]:0:M_C}" "$2" "${M_T[@]:M_C}"); M_W=("${M_W[@]:0:M_C}" "$3" "${M_W[@]:M_C}"); M_C=$(( M_C + 1 ))
            fi ;;
    esac
    if (( x )); then if (( M_C < an )); then M_S=$M_C M_E=$an; else M_S=$an M_E=$M_C; fi; else M_S=$M_C M_E=$M_C; fi
    if (( M_F > M_C )); then M_F=$M_C; fi
    m_cells "$M_F" "$M_C"
    while (( REPLY > SX - 3 && M_F < M_C )); do M_F=$(( M_F + 1 )); m_cells "$M_F" "$M_C"; done
}
# m_row -> MR_T (the row's display text: '<' / ' ', the shown clusters, the
# padding, '>' / ' '), MR_A (one symbol per cell), MR_X (CursorX)
m_row() {
    local i used=0 room=$(( SX - 2 )) y
    MR_T=' ' MR_A=$C4
    if (( M_F > 0 )); then MR_T='<'; else MR_A=$C2; fi
    for (( i = M_F; i < ${#M_T[@]}; i++ )); do
        if (( used + M_W[i] > room )); then break; fi
        MR_T+=${M_T[i]}
        y=$C2; if (( i >= M_S && i < M_E )); then y=$C3; fi
        MR_A+=$y; if (( M_W[i] == 2 )); then MR_A+=$y; fi
        used=$(( used + M_W[i] ))
    done
    for (( ; used < room; used++ )); do MR_T+=' ' MR_A+=$C2; done
    m_cells "$M_F" "${#M_T[@]}"
    if (( REPLY > room )); then MR_T+='>' MR_A+=$C4; else MR_T+=' ' MR_A+=$C2; fi
    m_cells "$M_F" "$M_C"; MR_X=$(( REPLY + 1 ))
}
UNITS=(a b c x y z ' ' ' ' . ж и я 中 文 字 😀)
WIDTH=(1 1 1 1 1 1 1 1 1 1 1 1 2 2 2 2)
KEYS=(kbChar kbChar kbChar kbChar kbChar kbChar kbChar kbLeft kbRight kbHome kbEnd kbShiftLeft kbShiftRight kbShiftHome kbShiftEnd
      kbCtrlLeft kbCtrlRight kbCtrlShiftLeft kbCtrlShiftRight kbBack kbBack kbDel kbIns kbCtrlS kbCtrlD)
fuzz() {      # SEED STEPS
    local seed=$1 steps=$2 st key u w join bad='' got cx full=0
    RANDOM=$seed
    scene 30
    M_T=() M_W=() M_C=0 M_F=0 M_S=0 M_E=0 M_I=0 M_MAX=30
    for (( st = 1; st <= steps; st++ )); do
        key=${KEYS[RANDOM % ${#KEYS[@]}]}
        if (( RANDOM % 97 == 0 )); then key=kbCtrlY; fi
        u='' w=''
        if [ "$key" = kbChar ]; then u=$(( RANDOM % ${#UNITS[@]} )); w=${WIDTH[u]} u=${UNITS[u]}; fi
        k "$key" "$u"
        case $key in kbCtrlS) key=kbLeft ;; kbCtrlD) key=kbRight ;; esac
        m_key "$key" "$u" "$w"
        local IFS=; join="${M_T[*]}"; IFS=$' \t\n'
        fv.dialogs.getText il; got=$RESULT
        m_row
        fvg_row $Y0
        cx=${il_data[CursorX]}
        if [[ $got != "$join" || ${il_data[CurPos]} != "$M_C" || ${il_data[FirstPos]} != "$M_F" || ${il_data[SelStart]} != "$M_S" || ${il_data[SelEnd]} != "$M_E" \
              || ${RESULT:X0:${#MR_T}} != "$MR_T" || ${REPLY:X0:SX} != "$MR_A" || $cx != "$MR_X" ]] \
           || (( (il_data[State] & FV_SF_CURSORINS) != (M_I ? FV_SF_CURSORINS : 0) )); then
            bad="seed $seed step $st key $key [$u]: text [$got] want [$join] cur ${il_data[CurPos]}/$M_C first ${il_data[FirstPos]}/$M_F sel ${il_data[SelStart]}-${il_data[SelEnd]}/$M_S-$M_E cx $cx/$MR_X row [${RESULT:X0:${#MR_T}}] want [$MR_T] syms [${REPLY:X0:SX}] want [$MR_A]"
            break
        fi
        if (( st % 40 == 0 )); then
            if ! fvw_full app; then bad="seed $seed step $st: != a full repaint $FVW_DIFF"; break; fi
            full=$(( full + 1 ))
        fi
    done
    unscene
    FUZZ_BAD=$bad FUZZ_FULL=$full
}
kt_test_section "007: editing and selection against the model"
for seed in 11 29 47; do
    kt_test_start "seed $seed: 220 random keys (ASCII, Cyrillic, CJK, emoji; moves, selection, words, Back, Del, overwrite, Ctrl+Y) == the model after each key"
    fuzz "$seed" 220
    if [[ -z $FUZZ_BAD ]]; then kt_test_pass "full repaints compared: $FUZZ_FULL"; else kt_test_fail "$FUZZ_BAD"; fi
done

kt_test_section "007: FV's rules"
scene 30
kt_test_start "typing 25 characters into the 20-cell line: FirstPos keeps CurPos within SizeX - 3 = 17 cells (FirstPos 8), '<' shown"
for (( i = 0; i < 25; i++ )); do k kbChar "${UNITS[i % 6]}"; done
fvg_cells $X0 $Y0 2
if [[ ${il_data[FirstPos]} == 8 && ${il_data[CurPos]} == 25 && ${il_data[CursorX]} == 18 && ${RESULT:0:1} == '<' ]] && fvw_full app; then kt_test_pass ok
else kt_test_fail "first ${il_data[FirstPos]} cur ${il_data[CurPos]} cx ${il_data[CursorX]} [$RESULT]"; fi
kt_test_start "Home: FirstPos 0, '>' in the last cell in colour 4"
k kbHome
fvg_cells $((X0 + SX - 1)) $Y0 1
if [[ ${il_data[FirstPos]} == 0 && $RESULT == '>' && $REPLY == "$C4" ]]; then kt_test_pass ok; else kt_test_fail "[$RESULT][$REPLY]"; fi
kt_test_start "MaxLen (30 clusters): the 31st character goes nowhere, the key handled"
k kbEnd; for (( i = 0; i < 6; i++ )); do k kbChar q; done
fv.dialogs.getText il
if [[ ${#il_cl[@]} == 30 && $RESULT == *qqqqq && $RESULT != *qqqqqq && $FV_EV_WHAT == evNothing ]]; then kt_test_pass ok; else kt_test_fail "${#il_cl[@]} [$RESULT] $FV_EV_WHAT"; fi
kt_test_start "overwrite at MaxLen replaces the cluster at the cursor (Ins, Home, x)"
k kbIns; k kbHome; k kbChar X
fv.dialogs.getText il
if [[ ${#il_cl[@]} == 30 && ${RESULT:0:1} == X && ${il_data[CurPos]} == 1 ]]; then kt_test_pass ok; else kt_test_fail "${#il_cl[@]} [$RESULT]"; fi
kt_test_start "the overwrite cursor: sfCursorIns -> fv.video type 2 (block, DECSCUSR 2); Ins again -> type 1 (underline)"
fv.views.resetCursor app; a=$__FV_VS_CURT
k kbIns; fv.views.resetCursor app; b=$__FV_VS_CURT
if [[ $a == 2 && $b == 1 ]] && (( ! (il_data[State] & FV_SF_CURSORINS) )); then kt_test_pass ok; else kt_test_fail "$a $b"; fi
kt_test_start "Ctrl+Y clears; WordStar Ctrl+V toggles overwrite (CtrlToArrow), Ctrl+H is Back"
k kbCtrlY; a=${#il_cl[@]}
k kbCtrlV; b=$(( il_data[State] & FV_SF_CURSORINS )); k kbCtrlV
k kbChar m; k kbChar n; k kbCtrlH
fv.dialogs.getText il
if [[ $a == 0 && $b != 0 && $RESULT == m ]]; then kt_test_pass ok; else kt_test_fail "$a $b [$RESULT]"; fi
kt_test_start "keys the line does not take pass on (Up, Down, Tab, Enter, F1, Alt+X, Ctrl+E: FV's Exit), the text unchanged"
r=''
for kk in kbUp kbDown kbTab kbEnter kbF1 kbAltX kbCtrlE; do
    fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=$kk FV_EV_CHAR='' FV_EV_BASE=''; fv.views._virt il HandleEvent
    r+="${FV_EV_WHAT} "
done
fv.dialogs.getText il
if [[ $r == 'evKeyDown evKeyDown evKeyDown evKeyDown evKeyDown evKeyDown evKeyDown ' && $RESULT == m ]]; then kt_test_pass ok; else kt_test_fail "$r [$RESULT]"; fi
kt_test_start "P3-12: a cursor move inside the text with no selection writes nothing (only CursorX); a typed character one write"
fv.dialogs.setText il 'hello'; fv.dialogs.selectAll il 0
k kbEnd
fvw_writes_on; FVW_WRITES=0; k kbLeft; w1=$FVW_WRITES; c1=${il_data[CursorX]}
FVW_WRITES=0; k kbChar Z; w2=$FVW_WRITES; fvw_writes_off
if [[ $w1 == 0 && $c1 == 5 && $w2 == 1 ]] && fvw_full app; then kt_test_pass "writes $w1 / $w2"; else kt_test_fail "writes $w1 / $w2 cx $c1 $FVW_DIFF"; fi
kt_test_start "a wide cluster never straddles the right edge: the row stops a cell early and pads"
fv.dialogs.setText il 'abcdefghijklmnopq中'; fv.dialogs.selectAll il 0
fvg_row $Y0
if [[ ${RESULT:X0:20} == ' abcdefghijklmnopq >' ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[${RESULT:X0:20}]"; fi
kt_test_start "End over it: the wide cluster shown, FirstPos moves by cells (17 - 2 + ...), the cursor after both halves"
k kbEnd
fvg_row $Y0
if [[ ${il_data[FirstPos]} == 2 && ${il_data[CursorX]} == 18 && ${RESULT:X0} == '<cdefghijklmnopq中  '* ]] && fvw_full app; then kt_test_pass ok
else kt_test_fail "first ${il_data[FirstPos]} cx ${il_data[CursorX]} [${RESULT:X0:20}]"; fi
unscene

kt_test_section "007: password mode (D29)"
scene 30
il_data[PasswordChar]='*'
kt_test_start "every cluster one '*' cell (CJK too); getText the real text; the cursor after the masked clusters"
for u in a 中 b 文; do k kbChar "$u"; done
fvg_cells $X0 $Y0 6
fv.dialogs.getText il
if [[ ${RESULT} == 'a中b文' && ${il_data[CursorX]} == 5 ]]; then fvg_cells $X0 $Y0 6; if [[ $RESULT == ' **** ' ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$RESULT]"; fi
else kt_test_fail "[$RESULT] cx ${il_data[CursorX]}"; fi
kt_test_start "the selection shows in colour 3 over the mask (Shift+Home)"
k kbShiftHome
fvg_cells $X0 $Y0 6
if [[ $REPLY == "$C2$C3$C3$C3$C3$C2" ]]; then kt_test_pass ok; else kt_test_fail "[$REPLY]"; fi
kt_test_start "FirstPos counts one cell per masked cluster: 25 wide characters -> FirstPos 8"
k kbCtrlY; for (( i = 0; i < 25; i++ )); do k kbChar 中; done
if [[ ${il_data[FirstPos]} == 8 && ${il_data[CursorX]} == 18 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "first ${il_data[FirstPos]} cx ${il_data[CursorX]}"; fi
unscene

kt_test_section "007: focus, data API, Valid"
scene 30
kt_test_start "SelectAll on focus (FV SetState sfSelected): Tab to the button and back selects the whole text; drawn"
fv.dialogs.setText il 'one two'; fv.dialogs.selectAll il 0; k kbEnd
k kbTab; k kbTab
fvg_cells $X0 $Y0 9
if [[ ${dlg_data[Current]} == il && ${il_data[SelStart]} == 0 && ${il_data[SelEnd]} == 7 && ${il_data[CurPos]} == 0 && $REPLY == "$C2$C3$C3$C3$C3$C3$C3$C3$C2" ]] && fvw_full app; then kt_test_pass ok
else kt_test_fail "cur ${dlg_data[Current]} sel ${il_data[SelStart]}-${il_data[SelEnd]} [$REPLY]"; fi
kt_test_start "typing over a selection replaces it"
k kbChar Q
fv.dialogs.getText il
if [[ $RESULT == Q ]]; then kt_test_pass ok; else kt_test_fail "[$RESULT]"; fi
kt_test_start "setText: control characters dropped, cut to MaxLen, all selected; getText; selectAll 0 / 1"
fv.dialogs.setText il $'a\tb\nc'"$(printf '%040d' 0)"
fv.dialogs.getText il; a=$RESULT
fv.dialogs.selectAll il 0; b="${il_data[SelStart]}-${il_data[SelEnd]}"
fv.dialogs.selectAll il 1; c="${il_data[SelStart]}-${il_data[SelEnd]}"
if [[ ${a:0:3} == abc && ${#a} == 30 && $b == 0-0 && $c == 0-30 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "[$a] $b $c"; fi
kt_test_start "the API keeps RESULT; refusals: not an input line, a bad ENABLE, a wrong count (rc 2)"
RESULT=keep; fv.dialogs.setText il x; fv.dialogs.selectAll il 1; a=$RESULT
r=''
fv.dialogs.getText ok || r+=$?; fv.dialogs.setText ok x || r+=$?; fv.dialogs.selectAll il 2 || r+=$?; fv.dialogs.getText || r+=$?
if [[ $a == keep && $r == 2222 ]]; then kt_test_pass ok; else kt_test_fail "$a $r"; fi
kt_test_start "the SelectAll alias (D16)"
il.SelectAll 0
if [[ ${il_data[SelEnd]} == 0 ]]; then kt_test_pass ok; else kt_test_fail "${il_data[SelEnd]}"; fi
kt_test_start "Valid with a Validator function: a text it refuses makes the dialog's Valid(cmOK) say no and selects the line; cmCancel is valid; a good text is valid"
digits() { [[ $1 != *[!0-9]* ]]; }
il_data[Validator]=digits
fv.views.focus ok
fv.dialogs.setText il 12a
r1=0; fv.views._virt dlg Valid cmOK || r1=$?; cur=${dlg_data[Current]}
r2=0; fv.views._virt dlg Valid cmCancel || r2=$?
fv.dialogs.setText il 123
r3=0; fv.views._virt dlg Valid cmOK || r3=$?
il_data[Validator]=no_such_fn
r4=0; fv.views._virt il Valid cmOK 2>/dev/null || r4=$?
il_data[Validator]=''
if [[ $r1 == 1 && $cur == il && $r2 == 0 && $r3 == 0 && $r4 == 0 ]]; then kt_test_pass ok; else kt_test_fail "$r1 $cur $r2 $r3 $r4"; fi
unscene

kt_test_log "007_InputLine.sh completed"
