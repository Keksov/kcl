#!/usr/bin/env bash
# 008_InputWide.sh - the input line's clusters (design P3 §4.1, P3-5, M6):
# after every edit the line's clusters and cells equal fv.video's split of
# the whole text (the oracle), so line and screen agree cell for cell:
#   * seeded random edits with joiners: ZWJ, VS16, an emoji modifier, a
#     combining mark, regional indicators (flags re-pair from the run's
#     start), wide and narrow pictographs, ASCII, Cyrillic, CJK — typed and
#     deleted mid-line (Back / Del), the cursor moved around; after each
#     edit ${il}_cl / _cw == fv.video.clusters of getText, CurPos within the
#     line, and now and then the screen == a full repaint;
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

kt_test_section "008: random edits with joiners"
UNITS=(a e 1 ж 中 "$W" "$B" "$HEART" "$ZWJ" "$ZWJ" "$VS16" "$SKIN" "$ACUTE" "$RU" "$RS" "$RD" "$RE" ' ')
KEYS=(kbChar kbChar kbChar kbChar kbChar kbChar kbLeft kbRight kbLeft kbHome kbEnd kbBack kbBack kbDel)
for seed in 5 23 71 88; do
    kt_test_start "seed $seed: 160 random edits (joiners, VS16, modifiers, combining marks, flags) == fv.video's split of the whole text after each"
    RANDOM=$seed
    scene 60
    bad='' full=0
    for (( st = 1; st <= 160; st++ )); do
        key=${KEYS[RANDOM % ${#KEYS[@]}]} u=''
        if [ "$key" = kbChar ]; then u=${UNITS[RANDOM % ${#UNITS[@]}]}; fi
        k "$key" "$u"
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

kt_test_log "008_InputWide.sh completed"
