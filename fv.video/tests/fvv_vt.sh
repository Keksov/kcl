#!/usr/bin/env bash
# fvv_vt.sh — a pure-bash VT model of exactly the sequences fv.video's screen
# buffer emits, as a test oracle (it replaces the spike's Python vt_replay).
# Not a test file: the ktests runner picks up NNN_*.sh only. Needs a UTF-8
# locale in the caller.
#
#   vt_init W H      a W x H grid of garbage (char '%', attribute 'G/G/G',
#                    cursor at 7,3, visibility unknown 'G', SGR state 'G'),
#                    so a cell or a state the stream does not set is caught
#   vt_feed STREAM   apply STREAM: CUP ESC[r;cH / ESC[H, CHA ESC[cG (default
#                    1, clamped to the row), SGR ESC[...m (0, 1, 22, 30-37,
#                    39, 40-47, 49, 90-97, 100-107, 38;5;N, 48;5;N),
#                    ESC[?25h / l, ESC[2J, and text (autowrap off: past the
#                    last column the last cell is overwritten);
#                    rc 1 and VT_ERR on anything else
#   Wide characters (P1c), from tables the TEST declares (never fv.unicode,
#   so the model stays independent of the unit):
#     VT_WD[ch]=0|1|2  the width a character has (default 1); a 2-wide one
#                      takes its cell and the next, which holds \x01; writing
#                      over either half of a wide character blanks the other
#                      half (as xterm / Windows Terminal do); a 0-wide one
#                      joins the cell written last (none after a cursor move)
#     VT_PICT[ch]=1    Extended_Pictographic: joins after a ZWJ (when the cell's
#                      base is one too), takes an emoji modifier (VT_MOD), and
#                      VS16 makes such a narrow base 2 wide (keycap bases
#                      0-9 # * too)
#     VT_MOD[ch]=1 / VT_RI[ch]=1  emoji modifiers / regional indicators (a
#                      second one after a lone one makes a 2-wide flag)
#     VT_DEV[ch]=W     a terminal that DISAGREES: draws ch W wide; VT_NOVS16=1:
#                      it ignores VS16. A cell drawn that way is noted in
#                      VT_DV (vt_cmp dev skips it, see below)
#   The text is walked on bytes (C locale), so a character past U+FFFF is one
#   character on every runtime.
#   vt_n16 INDEX     VT_N = the nearest of xterm's 16 default colours,
#                    computed here independently of the unit
#   vt_cmp [dev]     the grid and the cursor against fv.video's buffer: each
#                    cell's char (a marker \x02: its content in __FV_VS_X; a
#                    continuation: \x01), and fg/bg/bold from the symbol's
#                    palette entry (an undefined symbol: the default one's;
#                    with 16 colours through vt_n16); rc 1 and VT_ERR on the
#                    first difference. With dev: a cell the terminal draws
#                    with another width (its content in VT_DEV, or noted in
#                    VT_DV) is not checked itself; when the buffer has it
#                    wide, its second half must be a blank for a marker (the
#                    pre-blank) and is not checked for a plain wide
#                    character; every other cell is
#   vt_capture CMD…  CMD with FV_VIDEO_OUT_FD on a scratch file (FVV_TMP);
#                    VT_OUT = what it wrote, VT_RC = its status
#   vt_grid          VT_GRID = the grid as text (chars + attributes, the
#                    cursor visibility and, when visible, its position), for
#                    comparing two grids

VT_W=0 VT_H=0 VT_X=0 VT_Y=0 VT_VIS=G VT_FG=G VT_BG=G VT_B=G VT_ERR='' VT_OUT='' VT_RC=0 VT_N=0 VT_GRID=''
declare -a VT_C=() VT_A=()
declare -A VT_N16=() VT_WD=() VT_PICT=() VT_MOD=() VT_RI=() VT_DEV=()
declare -a VT_DV=()
# the cell written last (-1: none), its drawn width, its base, ends in a ZWJ,
# a lone regional indicator; a terminal that ignores VS16
VT_LC=-1 VT_LW=1 VT_LB='' VT_LZ=0 VT_LR=0 VT_NOVS16=0
VT_ZWJC=$'\xe2\x80\x8d' VT_VS16C=$'\xef\xb8\x8f'
VT_RE_CUP=$'^\e\\[([0-9]+);([0-9]+)H'
VT_RE_CHA=$'^\e\\[([0-9]*)G'
VT_RE_SGR=$'^\e\\[([0-9;]*)m'
# xterm's 16 defaults as "R G B" words; the cube levels
VT_PAL16=('0 0 0' '205 0 0' '0 205 0' '205 205 0' '0 0 238' '205 0 205' '0 205 205' '229 229 229'
    '127 127 127' '255 0 0' '0 255 0' '255 255 0' '92 92 255' '255 0 255' '0 255 255' '255 255 255')
VT_LEV=(0 95 135 175 215 255)

vt_init() {
    local i n=$(( $1 * $2 ))
    VT_W=$1 VT_H=$2 VT_X=7 VT_Y=3 VT_VIS=G VT_FG=G VT_BG=G VT_B=G VT_ERR=''
    VT_C=() VT_A=() VT_DV=() VT_LC=-1
    for (( i = 0; i < n; i++ )); do VT_C[i]=% VT_A[i]=G/G/G; done
}

vt_sgr() {
    local -a p
    local i n
    IFS=';' read -r -a p <<< "$1"
    if (( ${#p[@]} == 0 )); then p=(0); fi
    for (( i = 0; i < ${#p[@]}; i++ )); do
        n=${p[i]:-0}
        case $n in
            0) VT_FG=D VT_BG=D VT_B=0 ;;
            1) VT_B=1 ;;
            22) VT_B=0 ;;
            3[0-7]) VT_FG=$(( n - 30 )) ;;
            9[0-7]) VT_FG=$(( n - 82 )) ;;
            39) VT_FG=D ;;
            4[0-7]) VT_BG=$(( n - 40 )) ;;
            10[0-7]) VT_BG=$(( n - 92 )) ;;
            49) VT_BG=D ;;
            38|48)
                if [[ ${p[i+1]-} != 5 || -z ${p[i+2]-} || ${p[i+2]} == *[!0-9]* ]] || (( ${p[i+2]} > 255 )); then
                    VT_ERR="bad extended colour in SGR '$1'"; return 1
                fi
                if [[ $n == 38 ]]; then VT_FG=$(( 10#${p[i+2]} )); else VT_BG=$(( 10#${p[i+2]} )); fi
                i=$(( i + 2 )) ;;
            *) VT_ERR="unknown SGR parameter $n in '$1'"; return 1 ;;
        esac
    done
}

vt_feed() {
    local s=$1 h t c i j
    while [[ -n $s ]]; do
        if [[ $s == $'\e'* ]]; then
            h=${s:0:40}
            if [[ $h =~ $VT_RE_CUP ]]; then
                VT_Y=$(( 10#${BASH_REMATCH[1]} - 1 )) VT_X=$(( 10#${BASH_REMATCH[2]} - 1 ))
                if (( VT_Y < 0 )); then VT_Y=0; fi
                if (( VT_X < 0 )); then VT_X=0; fi
                if (( VT_Y >= VT_H )); then VT_Y=$(( VT_H - 1 )); fi
                if (( VT_X >= VT_W )); then VT_X=$(( VT_W - 1 )); fi
                s=${s:${#BASH_REMATCH[0]}} VT_LC=-1
            elif [[ $h =~ $VT_RE_CHA ]]; then
                VT_X=$(( 10#${BASH_REMATCH[1]:-1} - 1 ))
                if (( VT_X < 0 )); then VT_X=0; fi
                if (( VT_X >= VT_W )); then VT_X=$(( VT_W - 1 )); fi
                s=${s:${#BASH_REMATCH[0]}} VT_LC=-1
            elif [[ $h =~ $VT_RE_SGR ]]; then
                vt_sgr "${BASH_REMATCH[1]}" || return 1
                s=${s:${#BASH_REMATCH[0]}}
            elif [[ $h == $'\e[?25h'* ]]; then VT_VIS=h s=${s:6}
            elif [[ $h == $'\e[?25l'* ]]; then VT_VIS=l s=${s:6}
            elif [[ $h == $'\e[H'* ]]; then VT_X=0 VT_Y=0 s=${s:3} VT_LC=-1
            elif [[ $h == $'\e[2J'* ]]; then
                for (( i = 0; i < VT_W * VT_H; i++ )); do VT_C[i]=' ' VT_A[i]="$VT_FG/$VT_BG/$VT_B"; done
                s=${s:4} VT_LC=-1
            else
                printf -v VT_ERR 'unknown sequence %q' "${h:0:12}"
                return 1
            fi
        else
            t=${s%%$'\e'*}
            s=${s:${#t}}
            vt_text "$t"
        fi
    done
}

# vt_text TEXT — TEXT written at the cursor, one character (one UTF-8
# sequence, found on bytes) at a time
vt_text() {
    local LC_ALL=C t=$1 i=0 n b l c
    n=${#t}
    while (( i < n )); do
        printf -v b '%d' "'${t:i:1}"
        if (( b < 128 )); then l=1; elif (( b >= 240 )); then l=4; elif (( b >= 224 )); then l=3; elif (( b >= 192 )); then l=2; else l=1; fi
        c=${t:i:l} i=$(( i + l ))
        vt_put "$c"
    done
}

# vt_cut J — about to write cell J: when it is one half of a wide character,
# the other half becomes a space (its attribute stays)
vt_cut() {
    local j=$1 x=$(( $1 % VT_W ))
    if [[ ${VT_C[j]} == $'\x01' ]]; then
        if (( x > 0 )); then VT_C[j-1]=' '; unset 'VT_DV[j-1]'; fi
    elif (( x + 1 < VT_W )) && [[ ${VT_C[j+1]} == $'\x01' ]]; then
        VT_C[j+1]=' '
    fi
    unset 'VT_DV[j]'
}

# vt_widen — the cell written last becomes 2 wide (its second half taken)
vt_widen() {
    local k=$(( VT_LC + 1 ))
    if (( VT_LC % VT_W + 1 >= VT_W )); then return 0; fi
    vt_cut "$k"
    VT_C[k]=$'\x01' VT_A[k]=${VT_A[VT_LC]} VT_LW=2
    unset 'VT_DV[k]'
    if (( VT_X < VT_W - 1 )); then VT_X=$(( VT_X + 1 )); fi
}

# vt_put CH — one character at the cursor (VT_WD / VT_PICT / VT_MOD / VT_RI,
# a terminal's deviation VT_DEV / VT_NOVS16)
vt_put() {
    local c=$1 w d j a="$VT_FG/$VT_BG/$VT_B"
    d=${VT_WD[$c]-1} w=${VT_DEV[$c]-$d}
    if (( VT_LC >= 0 )); then
        if (( d == 0 )); then
            VT_C[VT_LC]+=$c VT_LZ=0
            if [[ $c == "$VT_ZWJC" ]]; then VT_LZ=1
            elif [[ $c == "$VT_VS16C" ]] && (( VT_LW == 1 )) && [[ -n ${VT_PICT[$VT_LB]-} || $VT_LB == [0123456789#*] ]]; then
                if (( VT_NOVS16 )); then VT_DV[VT_LC]=1; else vt_widen; fi
            fi
            return 0
        fi
        if { (( VT_LZ )) && [[ -n ${VT_PICT[$c]-} && -n ${VT_PICT[$VT_LB]-} ]]; } \
            || [[ -n ${VT_MOD[$c]-} && -n ${VT_PICT[$VT_LB]-} ]] || { [[ -n ${VT_RI[$c]-} ]] && (( VT_LR )); }; then
            VT_C[VT_LC]+=$c VT_LZ=0 VT_LR=0
            if [[ -n ${VT_PICT[$c]-} ]]; then VT_LB=$c; fi
            # a base drawn wide against its width ends as the 2-wide cell an
            # agreeing terminal draws after this join: no deviation left
            if (( VT_LW == 2 )) && [[ -n ${VT_MOD[$c]-}${VT_RI[$c]-} || $d == 2 ]]; then unset 'VT_DV[VT_LC]'; fi
            if (( VT_LW == 1 )); then
                # the joined cell is 2 wide unless the terminal draws its parts narrow
                if [[ -n ${VT_DEV[$c]-} ]] && (( w < 2 )); then VT_DV[VT_LC]=1
                elif (( w == 2 )) || [[ -n ${VT_MOD[$c]-}${VT_RI[$c]-} ]]; then vt_widen; fi
            fi
            return 0
        fi
    elif (( d == 0 )); then
        w=1                                   # a mark with nothing before it: a cell of its own
    fi
    j=$(( VT_Y * VT_W + VT_X ))
    vt_cut "$j"
    if (( w == 2 && VT_X + 1 < VT_W )); then vt_cut $(( j + 1 )); fi
    VT_C[j]=$c VT_A[j]=$a
    if (( w == 2 && VT_X + 1 < VT_W )); then VT_C[j+1]=$'\x01' VT_A[j+1]=$a; fi
    if (( w != d && d > 0 )); then VT_DV[j]=1; else unset 'VT_DV[j]'; fi
    VT_LC=$j VT_LW=$w VT_LB=$c VT_LZ=0 VT_LR=0
    if [[ -n ${VT_RI[$c]-} ]]; then VT_LR=1; fi
    VT_X=$(( VT_X + w ))
    if (( VT_X > VT_W - 1 )); then VT_X=$(( VT_W - 1 )); fi
}

vt_n16() {
    local i=$1 r g b k d best=0 bd=-1 pr pg pb
    if [[ -n ${VT_N16[$i]-} ]]; then VT_N=${VT_N16[$i]}; return 0; fi
    if (( i < 16 )); then VT_N=$i; VT_N16[$i]=$i; return 0; fi
    if (( i > 231 )); then
        r=$(( (i - 232) * 10 + 8 )); g=$r; b=$r
    else
        k=$(( i - 16 ))
        b=${VT_LEV[k % 6]}; k=$(( k / 6 ))
        g=${VT_LEV[k % 6]}; k=$(( k / 6 ))
        r=${VT_LEV[k]}
    fi
    for (( k = 15; k >= 0; k-- )); do              # downwards: <= keeps the lower index on a tie
        read -r pr pg pb <<< "${VT_PAL16[k]}"
        d=$(( (r - pr) * (r - pr) + (g - pg) * (g - pg) + (b - pb) * (b - pb) ))
        if (( bd < 0 || d <= bd )); then bd=$d best=$k; fi
    done
    VT_N=$best VT_N16[$i]=$best
}

# vt_want SYM -> VT_WANT "fg/bg/bold" as the terminal must show it
vt_want() {
    local p=${__FV_VS_PAL[$1]-} f b o
    if [[ -z $p ]]; then p=${__FV_VS_PAL[$__FV_VS_DEF]}; fi
    read -r f b o <<< "$p"
    if [[ $FV_VIDEO_COLORS == 16 ]]; then
        vt_n16 "$f"; f=$VT_N
        vt_n16 "$b"; b=$VT_N
    fi
    VT_WANT="$f/$b/$o"
}

vt_cmp() {
    local y x c a ch at s dev=${1-} k j pb=0
    local -A want=()
    VT_ERR=''
    if (( VT_W != __FV_VS_W || VT_H != __FV_VS_H )); then VT_ERR="grid ${VT_W}x$VT_H, buffer ${__FV_VS_W}x$__FV_VS_H"; return 1; fi
    for (( y = 0; y < VT_H; y++ )); do
        ch=${__FV_VS_CH[y]} at=${__FV_VS_AT[y]}
        if (( ${#ch} != VT_W || ${#at} != VT_W )); then VT_ERR="row $y: buffer lengths ${#ch}/${#at}"; return 1; fi
        for (( x = 0; x < VT_W; x++ )); do
            c=${ch:x:1} s=${at:x:1} j=$(( y * VT_W + x ))
            if [[ -z ${want[$s]-} ]]; then vt_want "$s"; want[$s]=$VT_WANT; fi
            a=${want[$s]}
            if [[ $c == $'\x02' ]]; then k="$y $x"; c=${__FV_VS_X[$k]-'<no side entry>'}; fi
            if (( pb )); then
                # the second half of a cell the terminal drew narrow: the pre-blank's
                # space for a marker, anything for a plain wide character
                if (( pb == 2 )) && [[ ${VT_C[j]} != ' ' || ${VT_A[j]} != "$a" ]]; then VT_ERR="row $y col $x: '${VT_C[j]}' ${VT_A[j]} after a narrow-drawn wide marker, want a blank in $a"; return 1; fi
                pb=0
                continue
            fi
            if [[ -n $dev ]] && [[ -n ${VT_DV[j]-} || -n ${VT_DEV[$c]-} ]]; then
                # a cell the terminal draws with another width (or a VS16 it
                # ignores) is not checked itself: drawn wide it may since have been
                # cut by the cell after it; drawn narrow, its second half follows
                if [[ ${ch:x+1:1} == $'\x01' ]]; then
                    pb=1
                    if [[ ${ch:x:1} == $'\x02' ]]; then pb=2; fi
                fi
                continue
            fi
            if [[ ${VT_C[j]} != "$c" ]]; then VT_ERR="row $y col $x: char '${VT_C[j]}' != '$c'"; return 1; fi
            if [[ ${VT_A[j]} != "$a" ]]; then VT_ERR="row $y col $x: attr ${VT_A[j]} != $a (sym $s)"; return 1; fi
        done
    done
    if (( __FV_VS_CURT )); then
        x=$__FV_VS_CURX y=$__FV_VS_CURY
        if (( x >= VT_W )); then x=$(( VT_W - 1 )); fi
        if (( y >= VT_H )); then y=$(( VT_H - 1 )); fi
        if [[ $VT_VIS != h || $VT_X != "$x" || $VT_Y != "$y" ]]; then VT_ERR="cursor: vt $VT_VIS $VT_X,$VT_Y, want h $x,$y"; return 1; fi
    elif [[ $VT_VIS != l ]]; then VT_ERR="cursor: vt $VT_VIS, want hidden"; return 1; fi
}

vt_capture() {
    local fd f=$FVV_TMP/vt_capture.out
    exec {fd}>"$f"
    VT_RC=0
    FV_VIDEO_OUT_FD=$fd "$@" || VT_RC=$?
    exec {fd}>&-
    VT_OUT=''
    IFS= read -r -d '' VT_OUT < "$f" || :
}

vt_grid() {
    local i n=$(( VT_W * VT_H ))
    VT_GRID="$VT_W $VT_H $VT_VIS"
    if [[ $VT_VIS == h ]]; then VT_GRID+=" $VT_X $VT_Y"; fi       # a hidden cursor stands where the text ended
    for (( i = 0; i < n; i++ )); do VT_GRID+="|${VT_C[i]}${VT_A[i]}"; done
}
