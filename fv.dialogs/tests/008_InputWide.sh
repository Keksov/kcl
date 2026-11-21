#!/usr/bin/env bash
# 008_InputWide.sh - the input line's clusters (design P3 §4.1, P3-5, M6):
# after every edit the line's clusters and cells equal fv.video's split of
# the whole text (the oracle), so line and screen agree cell for cell:
#   * seeded random edits with joiners: ZWJ, VS16, an emoji modifier, a
#     combining mark, regional indicators (flags re-pair from the run's
#     start), wide and narrow pictographs, ASCII, Cyrillic, CJK — typed and
#     deleted mid-line (Back / Del), overwrite, typing and pasting over a
#     selection, the cursor moved around; after each edit the text, CurPos
#     and the selection == a text model (FV's Delete, then Insert at the
#     same offset: F2), ${il}_cl / _cw == fv.video.clusters of getText, and
#     now and then the screen == a full repaint;
#   * F2: replace next to a dangling ZWJ / a lone indicator keeps the order;
#     F5: a 2-cell line with an orphan first cluster == a full repaint;
#   * the cases one by one: a ZWJ typed between two emoji joins them (one
#     cluster, 2 cells, the cursor after it), Back takes the whole cluster; a
#     modifier and VS16 join their base (a narrow pictograph becomes 2 cells,
#     D14); a combining mark joins its letter; flags typed one indicator at
#     a time pair up, an indicator typed in front of a run re-pairs it all,
#     a deleted flag leaves the others paired.
# Characters past U+FFFF are two bash characters on Cygwin-family runtimes:
# the same test runs there (fv.video walks such text on bytes).

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvg_testlib.sh"
fvg_init "$(basename "$0" .sh)" "$@"

kt_test_section "008: the input line's clusters == fv.video's split"

scene() {
    fvw_tscene 80 24
    TDialog.new dlg 10 4 70 18 'Edit'
    TInputLine.new il 3 2 33 3 "${1:-60}"
    fv.views.insert dlg il
    fv.views.select il
    fv.views.insert desk dlg; fv.views.select dlg
    fv.views.drawView app
}
unscene() { app.delete; if fv.views.isView dlg; then dlg.delete; fi; }
k() { fv.drivers.clearEvent; FV_EV_WHAT=evKeyDown FV_EV_KEY=$1 FV_EV_CHAR=${2-} FV_EV_BASE=''; fv.views._virt dlg HandleEvent; }
ZWJ=$'‍' VS16=$'️' SKIN=$'\U0001f3fd' ACUTE=$'́'
W=$'\U0001f469' B=$'\U0001f466' HEART=$'❤'
RU=$'\U0001f1fa' RS=$'\U0001f1f8' RD=$'\U0001f1e9' RE=$'\U0001f1ea' RF=$'\U0001f1eb'
# oracle -> rc 0 when the line's arrays equal fv.video's split of its text;
# ORA = what differs
oracle() {
    local -a cl cw
    local IFS=' '
    fv.dialogs.getText il
    fv.video.clusters "$RESULT" cl cw
    ORA=''
    if [[ "${cl[*]}" != "${il_cl[*]}" || "${cw[*]}" != "${il_cw[*]}" ]]; then
        printf -v ORA 'line %q / %s, split %q / %s' "${il_cl[*]}" "${il_cw[*]}" "${cl[*]}" "${cw[*]}"
        return 1
    fi
    if (( il_data[CurPos] < 0 || il_data[CurPos] > ${#il_cl[@]} )); then ORA="CurPos ${il_data[CurPos]} of ${#il_cl[@]}"; return 1; fi
}

# ---- the text model with joiners (F2) ------------------------------------------------
# T the expected text (characters); ML / MB its clusters (fv.video's split of
# the whole text) and their end offsets; C S E I the cursor, the selection,
# overwrite. An edit is FV's: Delete (Back / Del: the selection or a cluster;
# a character or a paste: overwrite's as many clusters at C as come in, else
# the selection), then Insert at that same offset, MaxLen kept; the cursor
# at the first cluster boundary at or after the edit's end
msplit() {
    ML=() MW=() MB=(0)
    if [[ -n $T ]]; then fv.video.clusters "$T" ML MW; fi
    local s o=0
    for s in "${ML[@]}"; do o=$(( o + ${#s} )); MB+=("$o"); done
}
mbnd() {   # OFF -> C
    local i
    for (( i = 0; i < ${#MB[@]}; i++ )); do if (( MB[i] >= $1 )); then C=$i; return 0; fi; done
    C=$(( ${#MB[@]} - 1 ))
}
mcut() { T=${T:0:$1}${T:$2}; msplit; mbnd "$1"; }   # A B (offsets)
mput() {   # TEXT
    local p=$1 a=${MB[C]} b j=0 n=${#ML[@]} m IFS=
    local -a pl=() pw=()
    fv.video.clusters "$p" pl pw
    p="${pl[*]}"
    if (( ! ${#pl[@]} )); then return 0; fi
    b=$a
    if (( I )); then
        j=$(( n - C )); if (( j > ${#pl[@]} )); then j=${#pl[@]}; fi
        b=${MB[C+j]}
    elif (( S < E )); then a=${MB[S]} b=${MB[E]} j=$(( E - S )); fi
    m=$(( MAXL - (n - j) ))
    if (( m <= 0 )); then if (( j )); then mcut "$a" "$b"; fi; return 0; fi
    if (( ${#pl[@]} > m )); then p="${pl[*]:0:m}"; fi
    T=${T:0:a}$p${T:b}; msplit; mbnd $(( a + ${#p} ))
}
mkey() {   # KEY [TEXT]
    local key=$1 x=0 an=0 n=${#ML[@]}
    case $key in kbShift*) x=1 key=${key/Shift/}; if (( C == E )); then an=$S; else an=$E; fi ;; esac
    case $key in
        kbLeft) if (( C > 0 )); then C=$(( C - 1 )); fi ;;
        kbRight) if (( C < n )); then C=$(( C + 1 )); fi ;;
        kbHome) C=0 ;;
        kbEnd) C=$n ;;
        kbBack) if (( S == E && C > 0 )); then S=$(( C - 1 )) E=$C; fi; if (( S < E )); then mcut "${MB[S]}" "${MB[E]}"; fi ;;
        kbDel) if (( S == E && C < n )); then S=$C E=$(( C + 1 )); fi; if (( S < E )); then mcut "${MB[S]}" "${MB[E]}"; fi ;;
        kbIns) I=$(( ! I )) ;;
        kbChar|PASTE) mput "$2" ;;
    esac
    if (( x )); then if (( C < an )); then S=$C E=$an; else S=$an E=$C; fi; else S=$C E=$C; fi
}
paste() { fv.drivers.clearEvent; FV_EV_WHAT=evCommand FV_EV_COMMAND=cmPasteText FV_EV_INFO=$1 FV_EV_ID=${#1}; fv.views._virt dlg HandleEvent; }

kt_test_section "008: random edits with joiners"
UNITS=(a e 1 ж 中 "$W" "$B" "$HEART" "$ZWJ" "$ZWJ" "$VS16" "$SKIN" "$ACUTE" "$RU" "$RS" "$RD" "$RE" ' ')
KEYS=(kbChar kbChar kbChar kbChar kbChar kbChar kbLeft kbRight kbLeft kbHome kbEnd kbBack kbBack kbDel kbIns kbShiftLeft kbShiftRight kbShiftLeft PASTE)
for seed in 5 23 71 88; do
    kt_test_start "seed $seed: 160 random edits (joiners, VS16, modifiers, combining marks, flags; overwrite, typing and pasting over a selection) == the text model after each, the clusters fv.video's split of the whole text"
    RANDOM=$seed
    scene 60
    bad='' full=0 T='' C=0 S=0 E=0 I=0 MAXL=60
    msplit
    for (( st = 1; st <= 160; st++ )); do
        key=${KEYS[RANDOM % ${#KEYS[@]}]} u=''
        if [ "$key" = kbChar ]; then u=${UNITS[RANDOM % ${#UNITS[@]}]}; fi
        if [ "$key" = PASTE ]; then
            u=${UNITS[RANDOM % ${#UNITS[@]}]}${UNITS[RANDOM % ${#UNITS[@]}]}${UNITS[RANDOM % ${#UNITS[@]}]}
            paste "$u"
        else k "$key" "$u"; fi
        mkey "$key" "$u"
        fv.dialogs.getText il
        if [[ $RESULT != "$T" ]] || (( il_data[CurPos] != C || il_data[SelStart] != S || il_data[SelEnd] != E )); then
            printf -v bad 'step %d key %s %q: text %q want %q, cur %s/%s sel %s-%s/%s-%s' "$st" "$key" "$u" "$RESULT" "$T" "${il_data[CurPos]}" "$C" "${il_data[SelStart]}" "${il_data[SelEnd]}" "$S" "$E"
            break
        fi
        if ! oracle; then printf -v bad 'step %d key %s %q: %s' "$st" "$key" "$u" "$ORA"; break; fi
        if (( st % 40 == 0 )); then
            if ! fvw_full app; then bad="step $st: != a full repaint $FVW_DIFF"; break; fi
            full=$(( full + 1 ))
        fi
    done
    unscene
    if [[ -z $bad ]]; then kt_test_pass "full repaints compared: $full"; else kt_test_fail "$bad"; fi
done

kt_test_section "008: the cases"
scene 60
kt_test_start "a ZWJ typed between two emoji joins them: one cluster of 2 cells, the cursor after it"
k kbChar "$W"; k kbChar "$B"; k kbLeft; k kbChar "$ZWJ"
if oracle && [[ ${#il_cl[@]} == 1 && ${il_cw[0]} == 2 && ${il_cl[0]} == "$W$ZWJ$B" && ${il_data[CurPos]} == 1 && ${il_data[CursorX]} == 3 ]] && fvw_full app; then kt_test_pass ok
else kt_test_fail "${#il_cl[@]} cw ${il_cw[*]} cur ${il_data[CurPos]} cx ${il_data[CursorX]} $ORA"; fi
kt_test_start "Back after it takes the whole ZWJ sequence"
k kbBack
if oracle && [[ ${#il_cl[@]} == 0 ]]; then kt_test_pass ok; else kt_test_fail "${#il_cl[@]} $ORA"; fi
kt_test_start "an emoji modifier joins its base; VS16 makes a narrow pictograph 2 cells (D14); a combining mark joins its letter"
k kbChar "$W"; k kbChar "$SKIN"; a="${#il_cl[@]}:${il_cw[*]}"
k kbChar "$HEART"; b=${il_cw[1]}; k kbChar "$VS16"; c="${#il_cl[@]}:${il_cw[1]}"
k kbChar e; k kbChar "$ACUTE"; d="${#il_cl[@]}:${il_cl[2]}"
if oracle && [[ $a == 1:2 && $b == 1 && $c == 2:2 && $d == "3:e$ACUTE" ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$a $b $c $d $ORA"; fi
k kbCtrlY
kt_test_start "flags typed one indicator at a time pair up: US then DE = two clusters of 2 cells"
for u in "$RU" "$RS" "$RD" "$RE"; do k kbChar "$u"; done
if oracle && [[ ${#il_cl[@]} == 2 && ${il_cl[0]} == "$RU$RS" && ${il_cl[1]} == "$RD$RE" && ${il_cw[*]} == '2 2' ]]; then kt_test_pass ok; else kt_test_fail "${#il_cl[@]} $ORA"; fi
kt_test_start "an indicator typed in front of the run re-pairs it all (F+U, S+D, E alone) == the whole split; the cursor after the new pair"
k kbHome; k kbChar "$RF"
if oracle && [[ ${#il_cl[@]} == 3 && ${il_cl[0]} == "$RF$RU" && ${il_cl[2]} == "$RE" && ${il_data[CurPos]} == 1 ]] && fvw_full app; then kt_test_pass ok
else kt_test_fail "${#il_cl[@]} cur ${il_data[CurPos]} $ORA"; fi
kt_test_start "Del of the first pair: the rest pairs from the run's start again"
k kbHome; k kbDel
if oracle && [[ ${#il_cl[@]} == 2 && ${il_cl[0]} == "$RS$RD" ]]; then kt_test_pass ok; else kt_test_fail "${#il_cl[@]} $ORA"; fi
kt_test_start "an ASCII character typed between two non-ASCII clusters goes the general way and stays its own cluster"
k kbCtrlY; k kbChar 中; k kbChar ж; k kbLeft; k kbChar x
if oracle && [[ ${il_cl[*]} == '中 x ж' && ${il_data[CurPos]} == 2 ]]; then kt_test_pass ok; else kt_test_fail "${il_cl[*]} $ORA"; fi
unscene

kt_test_section "008: replace next to a dangling ZWJ / a lone indicator (F2: FV's Delete, then Insert at the same offset)"
M=$'\U0001f468' RA=$'\U0001f1e6' RB=$'\U0001f1e7'
# rep -> REPLY = the text, its cluster count, CurPos
rep() { fv.dialogs.getText il; REPLY="$RESULT|${#il_cl[@]}|${il_data[CurPos]}"; }
kt_test_start "man ZWJ x woman, overwrite x by y: man ZWJ y woman (not man-ZWJ-woman y), the cursor after y"
scene 60; k kbChar "$M"; k kbChar "$ZWJ"; k kbChar x; k kbChar "$W"; k kbLeft; k kbLeft; k kbIns; k kbChar y; rep
if oracle && [[ $REPLY == "$M${ZWJ}y$W|3|2" ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "$(printf '%q' "$REPLY") $ORA"; fi
unscene
kt_test_start "the same with x selected: typing y over it, then pasting yz over the new y"
scene 60; k kbChar "$M"; k kbChar "$ZWJ"; k kbChar x; k kbChar "$W"; k kbLeft; k kbShiftLeft; k kbChar y; rep; a=$REPLY
k kbShiftLeft; paste yz; rep; b=$REPLY
if oracle && [[ $a == "$M${ZWJ}y$W|3|2" && $b == "$M${ZWJ}yz$W|4|3" ]]; then kt_test_pass ok; else kt_test_fail "$(printf '%q ' "$a" "$b") $ORA"; fi
unscene
kt_test_start "indicator A, x, indicator B: overwrite x by y keeps A y B (the indicators never pair across the edit)"
scene 60; k kbChar "$RA"; k kbChar x; k kbChar "$RB"; k kbLeft; k kbLeft; k kbIns; k kbChar y; rep
if oracle && [[ $REPLY == "${RA}y$RB|3|2" ]]; then kt_test_pass ok; else kt_test_fail "$(printf '%q' "$REPLY") $ORA"; fi
unscene
kt_test_start "overwrite of x by an indicator next to A pairs them (the new text splits with its neighbours)"
scene 60; k kbChar "$RA"; k kbChar x; k kbChar "$RB"; k kbLeft; k kbLeft; k kbIns; k kbChar "$RB"; rep
if oracle && [[ $REPLY == "$RA$RB$RB|2|1" ]]; then kt_test_pass ok; else kt_test_fail "$(printf '%q' "$REPLY") $ORA"; fi
unscene

kt_test_section "008: SizeX 2 (F5)"
kt_test_start "an orphan first cluster (VS16) at FirstPos 0 in a 2-cell line: no blank in front when no cluster is shown (== a full repaint)"
fvw_tscene 80 24
TDialog.new dlg 10 4 70 18 'Edit'
TInputLine.new il 3 2 5 3 6
fv.views.insert dlg il; fv.views.select il
fv.views.insert desk dlg; fv.views.select dlg
fv.views.drawView app
k kbChar "$VS16"; k kbHome
if [[ ${il_data[FirstPos]} == 0 ]] && fvw_full app; then kt_test_pass ok; else kt_test_fail "first ${il_data[FirstPos]} $FVW_DIFF"; fi
unscene

kt_test_log "008_InputWide.sh completed"
