#!/usr/bin/env bash
# 014_Perf.sh - the cost of the screen buffer (plan §5.2: limits 2-3x the
# targets, so runner noise cannot fail them; the numbers go to the log):
#   * a two-panel scene (frames, names, sizes, a selected row; Cyrillic and
#     box drawing; ~10 colour runs per row) composed with writes;
#   * a full repaint (updateScreen force) at 80x24 (target 15 ms, limit
#     45) and 200x50 (stretch target 30 ms, limit 90), with 256 and 16
#     colours;
#   * a 2-row partial update at 80x24 (two writeBuf + updateScreen; limit
#     12 ms);
#   * the plain control loop: printf of the precomputed frame to the same fd.
# Method: median of 5 rounds x N per measure in one process, interleaved
# with the control loop, frames to a file fd. FVV_PERF_N (default 6) sets N.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fvv_testlib.sh"
fvv_init "$(basename "$0" .sh)" "$@"
source "$FVV_TESTS_DIR/fvv_vt.sh"

kt_test_section "014: cost"

unset FV_COLORS FV_ASCII
N=${FVV_PERF_N:-6}
exec {pfd}>"$FVV_TMP/perf.out"
FV_VIDEO_OUT_FD=$pfd

# scene W H — the two-panel scene: per panel a frame, then rows of
# "name size" with alternating colours, a selected row, a status line
scene() {
    local w=$1 h=$2 y pw=$(( $1 / 2 )) i n line
    FV_SCREEN_W=$w FV_SCREEN_H=$h fv.video.initScreen
    fv.video.fillRect 0 0 "$w" "$(( h - 1 ))" 8
    for i in 0 1; do
        fv.video.writeStr $(( i * pw )) 0 "╔$(printf '%*s' $(( pw - 2 )) '' | sed 's/ /═/g')╗" 9
        fv.video.writeCStr $(( i * pw + 3 )) 0 ' ~П~анель ~'"$i"'~ ' 9 C
        for (( y = 1; y < h - 2; y++ )); do
            fv.video.writeStr $(( i * pw )) "$y" '║' 9
            fv.video.writeStr $(( i * pw + pw - 1 )) "$y" '║' 9
            n=$(( (y * 7 + i * 3) % 5 ))
            printf -v line '%-18.18s' "файл_$y.txt"
            fv.video.writeStr $(( i * pw + 2 )) "$y" "$line" "$( ((n)) && echo B || echo E)"
            fv.video.writeStr $(( i * pw + 21 )) "$y" "$(( y * 1234 ))" A
            fv.video.writeStr $(( i * pw + 30 )) "$y" '<DIR>' F
            fv.video.writeStr $(( i * pw + 37 )) "$y" "07.11.26 1$(( y % 10 )):0$(( y % 6 ))" 8
        done
        fv.video.writeStr $(( i * pw )) $(( h - 2 )) "╚$(printf '%*s' $(( pw - 2 )) '' | sed 's/ /═/g')╝" 9
    done
    pad ' selected файл ' 38
    fv.video.writeBuf 1 3 "$PAD" "$(printf '%038d' 0 | tr 0 G)"
    fv.video.writeCStr 0 $(( h - 1 )) "$(printf '%-*s' "$w" ' ~F1~ Help ~F3~ View ~F5~ Copy ~F10~ Quit')" P Q
    fv.video.updateScreen
}

us() { T=${EPOCHREALTIME//[.,]/}; }
# pad TEXT N -> PAD = TEXT cut or padded to N characters (printf pads bytes)
pad() { PAD=$1; while (( ${#PAD} < $2 )); do PAD+=' '; done; PAD=${PAD:0:$2}; }
# compose — every row written again from the saved row strings (24 / 50
# writeBuf of whole rows), no update: the cost of the writes
compose() {
    local y
    for (( y = 0; y < __FV_VS_H; y++ )); do fv.video.writeBuf 0 "$y" "${ROWC[y]}" "${ROWA[y]}"; done
}
# median of five values (microseconds) -> MED
med() { local s; s=$(printf '%s\n' "$@" | sort -n | sed -n 3p); MED=$s; }

# measure NAME CMD... — 5 rounds x N of CMD, each round followed by N plain
# printf of $FRAME; -> M_<NAME> and C_<NAME> (median us per call)
measure() {
    local name=$1 r i t0 t1 a=() c=()
    shift
    for (( r = 0; r < 5; r++ )); do
        us; t0=$T
        for (( i = 0; i < N; i++ )); do "$@"; done
        us; t1=$T; a+=($(( (t1 - t0) / N )))
        us; t0=$T
        for (( i = 0; i < N; i++ )); do printf '%s' "$FRAME" >&"$pfd"; done
        us; t1=$T; c+=($(( (t1 - t0) / N )))
    done
    med "${a[@]}"; printf -v "M_$name" '%s' "$MED"
    med "${c[@]}"; printf -v "C_$name" '%s' "$MED"
}
ms() { printf -v MS '%d.%02d' $(( $1 / 1000 )) $(( $1 % 1000 / 10 )); }

partial_k=3
partial() {
    local k=$partial_k
    fv.video.writeBuf 1 "$k" "$P_NORM" "$P_NORMA"
    k=$(( k % (__FV_VS_H - 4) + 1 ))
    fv.video.writeBuf 1 "$k" "$P_SEL" "$P_SELA"
    partial_k=$k
    fv.video.updateScreen
}

for depth in 256 16; do
    partial_k=3
    scene 80 24
    fv.video.setColorDepth "$depth"; fv.video.updateScreen
    ROWC=("${__FV_VS_CH[@]}") ROWA=("${__FV_VS_AT[@]}")
    vt_capture fv.video.updateScreen force; FRAME=$VT_OUT
    measure full80 fv.video.updateScreen force
    measure comp80 compose
    fv.video.updateScreen
    kt_test_start "80x24 full repaint, $depth colours: median <= 45 ms (target 15)"
    ms "$M_full80"; a=$MS; ms "$C_full80"; b=$MS; ms "$M_comp80"; c=$MS
    if (( M_full80 <= 45000 )); then kt_test_pass "repaint $a ms (plain printf of the frame $b ms, ${#FRAME} chars); 24 whole-row writeBuf $c ms"
    else kt_test_fail "repaint $a ms > 45 ms (plain $b ms)"; fi

    pad ' normal row файл' 38; P_NORM=$PAD P_NORMA=$(printf '%038d' 0 | tr 0 B)
    pad ' selected файл' 38; P_SEL=$PAD P_SELA=$(printf '%038d' 0 | tr 0 G)
    vt_capture partial; FRAME=$VT_OUT
    kt_test_start "the partial frame is two rows (CUP, runs), $depth colours"
    if [[ $VT_RC == 0 && $FRAME == $'\e['*';2H'*$'\e['*';2H'* ]]; then kt_test_pass "${#FRAME} chars"; else kt_test_fail "rc $VT_RC [${FRAME@Q}]"; fi
    measure part80 partial
    kt_test_start "80x24 2-row partial update (2 writeBuf + update), $depth colours: median <= 12 ms"
    ms "$M_part80"; a=$MS; ms "$C_part80"; b=$MS
    if (( M_part80 <= 12000 )); then kt_test_pass "$a ms (plain printf $b ms)"; else kt_test_fail "$a ms"; fi

    scene 200 50
    fv.video.setColorDepth "$depth"; fv.video.updateScreen
    vt_capture fv.video.updateScreen force; FRAME=$VT_OUT
    measure full200 fv.video.updateScreen force
    kt_test_start "200x50 full repaint, $depth colours: median <= 90 ms (stretch target 30)"
    ms "$M_full200"; a=$MS; ms "$C_full200"; b=$MS
    if (( M_full200 <= 90000 )); then kt_test_pass "$a ms (plain printf $b ms, ${#FRAME} chars)"; else kt_test_fail "$a ms"; fi
done
exec {pfd}>&-

kt_test_log "014_Perf.sh completed"
