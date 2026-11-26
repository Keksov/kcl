#!/usr/bin/env bash
# image_rt.sh — the round-trip / env-diff harness of the load-image tests on
# real units (kklass/docs/dev/IMAGE_PLAN.md §10; stages I2a-I3): ONE child
# script for every role, THE allow-list of the state compares, and the
# write-under-A / start-under-B pair. Not a test file (the ktests runner
# picks up NNN_*.sh only). Needs kcl_units.sh (kclt_setup, kclt_simrun)
# sourced and kclt_setup run. Used by 008_ImageRoundTrip, 009_ImageChain and
# the I3 tests 010-014.
#
# THE ALLOW-LIST (KCLT_IMG_ALLOW: variable-name globs left out of a compare of
# an image start with a normal load; nothing else is). Each entry and why it
# can differ between two processes that hold the same units:
#   __KK_UNIT_BOT     the loader's frame index of each unit while it loads;
#                     inert once the unit is complete (nothing reads it then);
#                     an image holds the writer's value (plan §4, M6)
#   __KK_UNIT_PID     pid state: a normal load records the loading shell's
#                     pid per unit; an image start leaves it absent (nothing
#                     reads it for a complete unit; never held, plan §4)
#   __KK_UNIT_IDX __KK_UNIT_CAND __KK_UNIT_IDX_OK __KK_UNIT_RES __KK_UNIT_HIT
#                     the unit-name index and the caller-keyed lookup caches:
#                     built per start from the lookups this process ran (a
#                     hit runs fewer); never held (plan §4)
#   __KK_FILE_PWD     caller-keyed: the folder each calling file was first
#                     seen from (a relative caller after a cd); never held
#   BASH_CMDS         bash's command hash table: filled by the commands a
#                     process ran (a normal load runs more); never held
#   PPID              the parent's pid: another process
#   __FV_VW_OWNER     fv.views' owner pid: its settings hook writes $BASHPID
#                     on every start (pid state, plan §5.1 (4))
#   __FV_AP_SOWN      fv.app's copy of that owner pid, taken when an
#                     application starts (fv.app._progCreate: use time, so only the
#                     state after RT_LAZY holds it — two normal loads differ
#                     there too; image I3)
# Plus, for function texts only: a CR byte kk._fn_text_cr wrote as ''<CR>''
# compares as the CR it stands for (__KK_IMG_CMPCR=1, IMG-D7: the same
# function, quoted so that the MSYS-family parsers keep it).
# The dump itself (kkore kk._img_state) never lists bash's dynamic variables,
# COLUMNS / LINES, RESULT, __kk_ft (kklass's pid- and fd-bound pair) or the
# image code's own names (__KK_IMG_*, __kk_im*): __KK_IMG_SKIP in
# kkore/kimage.sh, the same list the image writer compares with. The child
# leaves its own names out of its dump: __rt_* (its scratch) and RT_* (its
# inputs, exported by the harness: RT_REF names another file per process).
# Image I3 (env-diff over every unit, unchained and chained, lazy data,
# behaviour) found no other difference: an entry here is never added to make
# a diff go away.
KCLT_IMG_ALLOW=(__KK_UNIT_BOT __KK_UNIT_PID __KK_UNIT_IDX __KK_UNIT_CAND __KK_UNIT_IDX_OK __KK_UNIT_RES
    __KK_UNIT_HIT __KK_FILE_PWD BASH_CMDS PPID __FV_VW_OWNER __FV_AP_SOWN)

# kclt_imgscript — write $KCLT_TMP/rt.sh (the child, below) and
# $KCLT_TMP/cmp.sh A B (prints `cmp rc=N DIFF`: kk._img_cmp A B set with the
# allow-list), and make $KCLT_TMP/img (umask 077, as kk.image makes it: a
# umask 002 folder is refused in stat mode; the test's image folder) and
# $KCLT_TMP/d (the dumps), $KCLT_TMP/neutral2 (the cd target of `@rel`).
#
# rt.sh ROLE "P…" REQ DUMP — in a fresh bash (run it through kclt_simrun):
#   source kbool.sh; VERBOSE_KKLASS=${RT_VK-debug} (keyed: the same in every
#   role of a pair); eval "$RT_PREP"; kk.uses P… (when not empty); eval
#   "$RT_PRE"; cd "$RT_CD" (when set: a relative caller after a cd); then
#   kk.image REQ (ROLE image) or KBOOL_IMAGE=off kk.image REQ (ROLE plain: a
#   normal load). Prints
#     ROLE rc=N image|loaded imgs=+N  (a hit leaves no __KK_UNIT_PID entry;
#                                     imgs: the .img files KBOOL_IMAGE_DIR gained)
#     OUTCOME                         hit | miss wrote | miss nowrite: WHY |
#                                     plain: WHY | ? (kk.image's debug lines:
#                                     "loaded from", "…: a normal load, then
#                                     an image" + "wrote" / "no image
#                                     written: …", "WHY; a normal load"; ?
#                                     when VERBOSE_KKLASS is not debug)
#   then the state dump into DUMP (kk._img_state canon). RT_LAZY (shell
#   text): run after the dump, its output into DUMP.out, the state dumped
#   again into DUMP.lz (lazy data, behaviour). RT_REF (another process's
#   DUMP): this dump compared with it (`cmp rc=N DIFF`), and with RT_LAZY
#   also DUMP.lz (`lazy rc=N DIFF`) and DUMP.out as text (`out rc=N`; bash's
#   "warning: setlocale:" lines and empty lines left out).
kclt_imgscript() {
    ( umask 077 && mkdir -p "$KCLT_TMP/img" "$KCLT_TMP/d" "$KCLT_TMP/neutral2" )
    # (the configs of B2 and of the key cases: cfg0's merged effect is the
    # default one — a comment, empty list values; cfg1 adds a define, a key row)
    printf '%s\n' '# image I3: a config without a merged effect' 'defines =' 'unitpath =' > "$KCLT_TMP/cfg0"
    printf '%s\n' 'defines = I3_FLAG' > "$KCLT_TMP/cfg1"
    KCLT_IMG_B2+=(KBOOL_CONFIG="$KCLT_TMP/cfg0")
    {
        printf '%s\n' 'source "$KBOOL_ROOT/kbool.sh" || exit 2' \
            'VERBOSE_KKLASS=${RT_VK-debug}'
        printf '__rt_allow=('
        printf ' %q' "${KCLT_IMG_ALLOW[@]}"
        printf ' )\n'
        cat <<'EOF'
if [[ -n ${RT_PREP-} ]]; then eval "$RT_PREP"; fi
if [[ -n $2 ]]; then kk.uses $2 >/dev/null 2>&1 || { echo "$1 P failed"; exit 3; }; fi
if [[ -n ${RT_PRE-} ]]; then eval "$RT_PRE"; fi
if [[ -n ${RT_CD-} ]]; then cd "$RT_CD" || exit 4; fi
__rt_n0=0 __rt_n1=0
for __rt_x in "$KBOOL_IMAGE_DIR"/*.img; do [[ -e $__rt_x ]] && __rt_n0=$(( __rt_n0 + 1 )); done
if [[ $1 == plain ]]; then KBOOL_IMAGE=off kk.image "$3" >/dev/null 2>"$4.err"; else kk.image "$3" >/dev/null 2>"$4.err"; fi
__rt_r=$?
for __rt_x in "$KBOOL_IMAGE_DIR"/*.img; do [[ -e $__rt_x ]] && __rt_n1=$(( __rt_n1 + 1 )); done
__rt_o="" __rt_w=""
while IFS= read -r __rt_x; do
    [[ $__rt_x == "kbool: image: "* ]] || continue
    __rt_x=${__rt_x#kbool: image: }
    case $__rt_x in
        "loaded from "*) __rt_o=hit ;;
        *": a normal load, then an image") __rt_o="miss" ;;
        wrote*) __rt_w=" wrote" ;;
        "no image written"*) __rt_w=" nowrite: ${__rt_x#no image written: }" ;;
        *"; a normal load (kk.uses "*) [[ -n $__rt_o ]] || __rt_o="plain: ${__rt_x%; a normal load (kk.uses *}" ;;
    esac
done < "$4.err"
if [[ -n ${__KK_UNIT_PID[$3]+x} ]]; then __rt_x=loaded; else __rt_x=image; fi
echo "$1 rc=$__rt_r $__rt_x imgs=+$(( __rt_n1 - __rt_n0 ))"
echo "${__rt_o:-?}$__rt_w"
kk._image_lib || exit 2
__KK_IMG_XV=('__rt_*' 'RT_*')
kk._img_state "$4" canon
if [[ -n ${RT_LAZY-} ]]; then
    { eval "$RT_LAZY"; } > "$4.out" 2>&1
    kk._img_state "$4.lz" canon
fi
if [[ -n ${RT_REF-} ]]; then
    __KK_IMG_CMPV=("${__rt_allow[@]}") __KK_IMG_CMPCR=1
    kk._img_cmp "$RT_REF" "$4" set
    echo "cmp rc=$? $__KK_IMG_DIFF"
    if [[ -n ${RT_LAZY-} ]]; then
        kk._img_cmp "$RT_REF.lz" "$4.lz" set
        echo "lazy rc=$? $__KK_IMG_DIFF"
        # (bash's "warning: setlocale: …" lines left out: a B locale this
        # system lacks — ru_RU.UTF-8 on a Linux runner — warns whenever a
        # function's `local LC_ALL` returns; the units read the variable's
        # text alone)
        __rt_nl() {
            local - IFS=$'\n' __rt_l __rt_s=""
            set -f
            IFS= read -r -d '' __rt_s < "$1" || :
            REPLY=""
            for __rt_l in $__rt_s; do [[ $__rt_l == *"warning: setlocale: "* ]] || REPLY+=$__rt_l$'\n'; done
        }
        __rt_nl "$RT_REF.out"; __rt_a=$REPLY
        __rt_nl "$4.out"; __rt_b=$REPLY
        if [[ $__rt_a == "$__rt_b" ]]; then echo "out rc=0"; else echo "out rc=1 '${__rt_a:0:300}' vs '${__rt_b:0:300}'"; fi
    fi
fi
EOF
    } > "$KCLT_TMP/rt.sh"
    kclt_imgcmpscript
}

# kclt_imgcmpscript — $KCLT_TMP/cmp.sh A B: kk._img_cmp A B set (two canon
# dumps of two processes) with THE allow-list; prints `cmp rc=N DIFF`.
# (008 and 009 write their own children and use this compare.)
kclt_imgcmpscript() {
    {
        printf '%s\n' 'source "$KBOOL_ROOT/kbool.sh" || exit 2' 'kk._image_lib || exit 2'
        printf '__KK_IMG_CMPV=('
        printf ' %q' "${KCLT_IMG_ALLOW[@]}"
        printf ' )\n'
        printf '%s\n' '__KK_IMG_CMPCR=1' 'kk._img_cmp "$1" "$2" set' 'echo "cmp rc=$? $__KK_IMG_DIFF"'
    } > "$KCLT_TMP/cmp.sh"
}

# kclt_img NAME [ENV…] -- ROLE "P…" REQ — rt.sh in a hermetic bash
# (kclt_simrun; KBOOL_IMAGE_DIR = the test's image folder), the dump into
# $KCLT_TMP/d/NAME. ENV: NAME=VALUE items for the child's environment, and
# `@rel` = a relative caller after a cd: the child starts in $KCLT_TMP as
# `./rt.sh` and cds to $KCLT_TMP/neutral2 before kk.image (else: the
# neutral folder, the script by its absolute path). Sets OUT (the lines
# joined by " | "), ERR, RC, IMG_L1 / IMG_L2 (the first two lines), IMG_CMP
# (the `cmp` line), IMG_LZ (`lazy`), IMG_OUT (`out`).
kclt_img() {
    local n=$1 s=$KCLT_TMP/rt.sh KCLT_CWD=${KCLT_CWD-} x
    local -a e=() l=()
    shift
    while (( $# )) && [[ $1 != -- ]]; do
        if [[ $1 == @rel ]]; then
            KCLT_CWD=$KCLT_TMP s=./rt.sh e+=(RT_CD="$KCLT_TMP/neutral2")
        else
            e+=("$1")
        fi
        shift
    done
    shift
    kclt_simrun KBOOL_IMAGE_DIR="$KCLT_TMP/img" "${e[@]}" -- "$s" "$1" "$2" "$3" "$KCLT_TMP/d/$n"
    IMG_L1="" IMG_L2="" IMG_CMP="" IMG_LZ="" IMG_OUT=""
    while IFS= read -r x; do
        l+=("$x")
        case $x in
            "cmp rc="*) IMG_CMP=$x ;;
            "lazy rc="*) IMG_LZ=$x ;;
            "out rc="*) IMG_OUT=$x ;;
        esac
    done <<< "$OUT"
    IMG_L1=${l[0]-} IMG_L2=${l[1]-}
    OUT=${OUT//$'\n'/ | }
}

# kclt_imgw ID "P…" REQ [ENV…] — the writer: REQ on P started under ENV (the
# environment A) with an empty image folder for its key; IMG_W = "wrote",
# "cr" (no image: a raw CR function this parser drops and no kklass in the
# closure — kclt_crdrop; plan §6.3), "crbase" (no image, chained: a variable
# of P's this call's files name holds a CR byte — the read base cannot keep
# it; I2b deviations 7, 13), "hit" (an image of the key is there
# already: an earlier case wrote it), else the child's output.
kclt_imgw() {
    local id=$1 p=$2 u=$3
    shift 3
    kclt_img "$id.w" "$@" -- image "$p" "$u"
    case $OUT in
        "image rc=0 loaded imgs=+1 | miss wrote") IMG_W=wrote ;;
        "image rc=0 loaded imgs=+0 | miss nowrite: a function text holds a CR byte this parser drops, and kklass (kk._fn_text_cr) is not loaded")
            IMG_W=cr ;;
        "image rc=0 loaded imgs=+0 | miss nowrite: the earlier value of "*", which this call's load reads, holds a CR byte (the base list is one compound array)")
            IMG_W=crbase ;;
        "image rc=0 loaded imgs=+0 | miss nowrite: bash "*" prints \`1<> FILE\` as \`<> FILE\` (fd 0 when read back): no image of a function text with \` <> \`")
            IMG_W=rw ;;
        "image rc=0 image imgs=+0 | hit") IMG_W=hit ;;
        *) IMG_W="W='$OUT' err='${ERR//$'\n'/|}'" ;;
    esac
}

# kclt_imgab TITLE ID "P…" REQ WANT [ENV…] — the start under B (ENV) and a
# normal load under B (KBOOL_IMAGE=off, its dump compared in the same child
# with the start's: RT_REF); one test. WANT: the start's outcome —
#   hit             a hit (no .img written)
#   miss            a miss that wrote another image (another key)
#   plain:TEXT      a plain kk.uses whose reason starts with TEXT (nothing written)
#   nowrite         a miss whose writer refused again (no image: the cr / crbase
#                   cases of kclt_imgw under another key)
#   missq / nowriteq  miss / nowrite told by the files alone (VERBOSE_KKLASS
#                   not debug: no reason printed)
# and, always: the same rc, the states equal but for the allow-list (with
# RT_LAZY in ENV also the state after it and its output). After a writer
# whose IMG_W is cr (no image for this key on this parser) a WANT of hit
# becomes plain:"no image …" (the key's hold: the same normal load).
kclt_imgab() {
    local t=$1 id=$2 p=$3 u=$4 want=$5 h r x ok=1 why=""
    shift 5
    if [[ $want == hit && ( ${IMG_W-} == cr || ${IMG_W-} == crbase || ${IMG_W-} == rw ) ]]; then want="plain:no image "; fi
    kclt_img "$id.h" "$@" -- image "$p" "$u"
    h=$OUT
    case $want in
        hit)     [[ $IMG_L1 == "image rc=0 image imgs=+0" && $IMG_L2 == hit ]] || ok=0 ;;
        miss)    [[ $IMG_L1 == "image rc=0 loaded imgs=+1" && $IMG_L2 == "miss wrote" ]] || ok=0 ;;
        plain:*) [[ $IMG_L1 == "image rc=0 loaded imgs=+0" && $IMG_L2 == "plain: ${want#plain:}"* ]] || ok=0 ;;
        nowrite) [[ $IMG_L1 == "image rc=0 loaded imgs=+0" && $IMG_L2 == "miss nowrite: "* ]] || ok=0 ;;
        missq)   [[ $IMG_L1 == "image rc=0 loaded imgs=+1" && $IMG_L2 == "?" ]] || ok=0 ;;
        nowriteq) [[ $IMG_L1 == "image rc=0 loaded imgs=+0" && $IMG_L2 == "?" ]] || ok=0 ;;
    esac
    (( ok )) || why="start='$h' want=$want err='${ERR//$'\n'/|}'"
    kclt_img "$id.r" "$@" RT_REF="$KCLT_TMP/d/$id.h" -- plain "$p" "$u"
    r=$OUT
    if [[ $IMG_L1 != "plain rc=0 loaded imgs=+0" || $IMG_CMP != "cmp rc=0 " ]]; then
        ok=0 why+=" normal='$r' err='${ERR//$'\n'/|}'"
    elif [[ -n $IMG_LZ$IMG_OUT && ( $IMG_LZ != "lazy rc=0 " || $IMG_OUT != "out rc=0" ) ]]; then
        ok=0 why+=" lazy='$IMG_LZ' out='$IMG_OUT'"
    fi
    kt_test_start "$t"
    if (( ok )); then
        x=""
        if [[ -n $IMG_OUT ]]; then IFS= read -r -d '' x < "$KCLT_TMP/d/$id.r.out" || :; x=" (lazy output ${#x} characters)"; fi
        kt_test_pass "ok$x"
    else
        kt_test_fail "$why"
    fi
}

# kclt_crdrop — rc 0 when this bash drops a CR byte from a function text it
# parses (the MSYS-family parsers; plan M7): an image of a closure with such a
# function and without kklass (kk._fn_text_cr) is refused there (§6.3).
kclt_rwbug() {
    local __kclt_t=""
    eval '__kclt_rw() { : 1<> /dev/null; }'
    __kclt_t=$(declare -f __kclt_rw)
    unset -f __kclt_rw
    [[ $__kclt_t != *'1<>'* ]]
}
kclt_crdrop() {
    local __kclt_t=""
    eval "__kclt_cr() { __kclt_t='a"$'\r'"b'; }"
    __kclt_cr
    unset -f __kclt_cr
    [[ $__kclt_t != *$'\r'* ]]
}

# kclt_closure UNIT… — KCLOSURE: " NAME " for every unit a bare load of the
# UNITs loads (the kcl table's units, kclt_order; kklass for every row: each
# kcl unit with classes loads it — the table rows all do, through
# kklass_pascal or a dependency).
kclt_closure() {
    local u
    KORDER=()
    for u in "$@"; do kclt_order "$u"; done
    KCLOSURE=" kklass ${KORDER[*]} "
}

# KCLT_IMG_B1 / KCLT_IMG_B2 — the two "same key" environments B (A is the
# hermetic default of kclt_simrun: no locale, no FV_*, the neutral folder,
# the script by its absolute path). Nothing here is a key row (plan §7.1), so
# a start under B hits and the settings hooks make the state a normal load's:
#   B1  LANG=ru_RU.UTF-8 (kk.localeDefault exports nothing; fv.keyboard's
#       layout and fv.video's locale follow it), NO_COLOR / TERM / COLUMNS
#       (read at use time only: fv.dlg, fv.video), FV_HISTORY_SIZE and
#       FV_SCREEN_W exported (hook VARs: the hooks keep them), caller
#       globals the hooks keep (FV_MSGBOX_TITLES, TUTIL_OUT_PREFIXES with an
#       extra prefix, FV_DLG_TAGS, FV_DLG_CMD), a relative caller after a cd
#   B2  LC_ALL=C (no UTF-8: fv.video's ASCII mode), FV_ASCII=1, TERM=dumb,
#       FV_KBD_LAYOUT preset (read at use time), and (kclt_imgscript) a
#       KBOOL_CONFIG whose merged effect is the default one (a comment,
#       empty list values: $KCLT_TMP/cfg0)
KCLT_IMG_B1=(LANG=ru_RU.UTF-8 NO_COLOR=1 TERM=xterm-256color COLUMNS=100 FV_HISTORY_SIZE=7 FV_SCREEN_W=100
    "RT_PRE=FV_MSGBOX_TITLES=(Achtung Fehler Info Frage); TUTIL_OUT_PREFIXES=(__tu_ __tg_ __th_ __tt_ __i3_); FV_DLG_TAGS=(x); FV_DLG_CMD=prev"
    @rel)
KCLT_IMG_B2=(LC_ALL=C FV_ASCII=1 TERM=dumb FV_KBD_LAYOUT=de)

# KCLT_IMG_LAZY[UNIT] — the lazy data of a unit (state its load leaves empty
# and its first use fills; never in an image: written right after the load,
# plan §4) and its behaviour, as RT_LAZY shell text: run after the start
# and after the normal load of a B pair, both outputs and both states after
# it compared (kclt_imgab). The first use after an image start must load
# what it loads after a normal load:
#   tregex       the word-boundary probe (TRegEx._wbProbe -> __TRE_WB_MODE)
#   tpath        the stat flavour (tpath._statFlavour -> __TP_STAT; a fork)
#   math         the float engine (an awk co-process, started on first use and
#                stopped again: no process outlives the child)
#   tutil        the sed options (tutil._sedOpts -> __TUTIL_SED_OPTS)
#   fv.unicode   the mixed-page width cache (__FV_UC_E, expanded on lookup)
#   fv.video     the ASCII-mode map (fv.video._amap -> __FV_VS_AMAP)
#   fv.keyboard  the layout tables (fv.keyboard.layoutBase: FV_KBD_LAYOUT,
#                then the locale's layout — B1's LANG=ru_RU.UTF-8)
#   fv.dlg       the usage text (a file sourced on --help), and headless
#                widgets through fv.dlg's own test lib (fvdlg_testlib.sh:
#                scripted keys, the screen's rows and palette symbols — fv.views'
#                palette cache PAL filled on first draw, NO_COLOR in B1), the
#                three lazy tables above in the fv.dlg closure
declare -gA KCLT_IMG_LAZY=()
KCLT_IMG_LAZY[tregex]='TRegEx.isMatch "a foo b" "\bfoo\b"; echo "isMatch=$? mode=${__TRE_WB_MODE-}"'
KCLT_IMG_LAZY[tpath]='tpath._statFlavour; echo "flavour=$? $__TP_STAT"'
KCLT_IMG_LAZY[math]='math.sqrt 2; echo "sqrt=$? $RESULT"; math.feStop; echo "stop=$?"'
KCLT_IMG_LAZY[tutil]='tutil._sedOpts; echo "sed=$? ${__TUTIL_SED_OPTS-}"'
KCLT_IMG_LAZY[fv.unicode]='for c in 769 4352 12354 128512 917760; do fv.unicode.charWidth "$c"; echo "$c=$? $RESULT"; done'
KCLT_IMG_LAZY[fv.video]='fv.video._amap; echo "amap=${#__FV_VS_AMAP[@]}"'
KCLT_IMG_LAZY[fv.keyboard]='for c in q "й" "ä"; do fv.keyboard.layoutBase "$c"; echo "$c=$? $RESULT"; done'
KCLT_IMG_LAZY[fv.dlg]=${KCLT_IMG_LAZY[fv.unicode]}'
'${KCLT_IMG_LAZY[fv.video]}'
'${KCLT_IMG_LAZY[fv.keyboard]}'
fv.dlg.main --help; echo "help=$?"
source "$KCL_DIR/fv.dlg/tests/fvdlg_testlib.sh" || echo "no test lib"
fvdl_run snap "key kbEnter" -- --title Hello --msgbox "Hello, world!\nA second line." 0 0
echo "msgbox rc=$FVDL_RC res=$FVDL_RES cmd=$FVDL_CMD"; echo "$FVDL_SNAP"; echo "$FVDL_SNAPA"
fvdl_run snap "key kbDown" "char _" "key kbEnter" -- --checklist "Choose some:" 0 0 0 a Apple on b Banana off c Cherry off
echo "checklist rc=$FVDL_RC res=$FVDL_RES tags=${FV_DLG_TAGS[*]}"; echo "$FVDL_SNAP"; echo "$FVDL_SNAPA"
fvdl_run snap "char x" "char y" "key kbEnter" -- --inputbox "Name?" 0 0 abc
echo "inputbox rc=$FVDL_RC res=$FVDL_RES"; echo "$FVDL_SNAP"
fvdl_run snap "key kbTab" "key kbEnter" -- --defaultno --yesno "Proceed?" 0 0
echo "yesno rc=$FVDL_RC res=$FVDL_RES cmd=$FVDL_CMD"; echo "$FVDL_SNAPA"'

# kclt_imgenv "P…" UNIT CASE… — the env-diff of UNIT on the prior set P
# (empty: unchained): ONE image written under A (kclt_imgw; P loaded there
# too) and started under every CASE B, each against a normal load under the
# same B (kclt_imgab):
#   b1     KCLT_IMG_B1 (+ the unit's KCLT_IMG_LAZY): a hit
#   b2     KCLT_IMG_B2 (+ the lazy text): a hit
#   key    KBOOL_CONFIG=cfg1 (a define: the merged config is a key row): a
#          miss that writes another image
#   clash  a caller global named like a scalar the image creates (its first
#          `declare -g NAME=` line, kklass's own KK* names skipped), set
#          before kk.image: a plain kk.uses ("exists in this shell
#          already"), nothing written
#   bp     (chained) KCLT_IMG_B1 with its caller presets set BEFORE P loads
#          (RT_PREP: P's hooks keep them): a hit
#   off    (chained) KBOOL_IMAGE_CHAIN=off: a plain kk.uses
#   mode   KBOOL_IMAGE_CHECK=hash (the effective check mode is keyed; the
#          runtimes default to dates or stat): a miss that writes another image
#   modex  KBOOL_IMAGE_CHECK=bogus (an invalid value runs as the default: the
#          same key): a hit
#   vk     VERBOSE_KKLASS set empty instead of debug (keyed): a miss that
#          writes another image (no debug lines: told by the files alone)
#   clashx the clash case through an EXPORTED preset of that scalar (an
#          environment preset of a unit variable): a plain kk.uses
# An image refused for a raw CR function (IMG_W cr; kclt_imgw) is pinned to
# KCLT_IMG_CRUNITS on a CR-dropping parser (a written image elsewhere); its
# B starts are then plain loads (the key's hold) — still equal. Likewise a
# chained image refused for a CR byte in a read-base value (IMG_W crbase) is
# pinned to KCLT_IMG_CRBASE ("P|UNIT"), on every parser: tsed names tutil's
# __TUTIL_CR_SED ('s/\r$//' with a raw CR), so `kk.uses tutil; kk.image
# tsed` never gets an image (a known limit, image I3).
KCLT_IMG_CRUNITS=" fv.keyboard fv.drivers "
KCLT_IMG_CRBASE=" tutil|tsed "
# And on a bash whose declare -f prints `1<> FILE` as `<> FILE` (bash 5.2;
# kclt_rwbug) the units whose own files hold such a redirection get no image
# (kkore kk._img__rwbug; image I3): KCLT_IMG_RWUNITS, chained or not.
KCLT_IMG_RWUNITS=" tfile "
kclt_imgenv() {
    local p=$1 u=$2 c id t img="" x v="" lz=${KCLT_IMG_LAZY[$2]-}
    shift 2
    id=${p// /+}${p:+_}$u
    t="${p:+kk.uses $p; }kk.image $u"
    kclt_imgw "$id" "$p" "$u"
    x=0 v=""
    if [[ -z $p && $KCLT_IMG_CRUNITS == *" $u "* ]] && kclt_crdrop; then
        x=1 v="; on this CR-dropping parser refused: a raw CR function and no kklass in the closure"
    elif [[ $KCLT_IMG_CRBASE == *" $p|$u "* ]]; then
        x=2 v="; refused: a variable of P's its files name holds a CR byte (the read base cannot keep it)"
    elif [[ $KCLT_IMG_RWUNITS == *" $u "* ]] && kclt_rwbug; then
        x=3 v="; on this bash refused: its declare -f prints \`1<> FILE\` as \`<> FILE\`"
    fi
    kt_test_start "$t: written under A (no locale, the neutral folder)$v [§6.2, §6.3]"
    if [[ $IMG_W == wrote && $x == 0 ]] || [[ $IMG_W == cr && $x == 1 ]] || [[ $IMG_W == crbase && $x == 2 ]] || [[ $IMG_W == rw && $x == 3 ]]; then
        kt_test_pass "ok ($IMG_W)"
    else
        kt_test_fail "$IMG_W"
        return 0
    fi
    for c in "$@"; do
        case $c in
            b1) kclt_imgab "$t: started under B1 (LANG=ru_RU.UTF-8, NO_COLOR, TERM, COLUMNS, hook VARs preset, a relative caller after a cd${lz:+; then its lazy data}): a hit, the state a normal load's under B1 [§10 env-diff]" \
                    "$id.b1" "$p" "$u" hit "${KCLT_IMG_B1[@]}" ${lz:+"RT_LAZY=$lz"} ;;
            b2) kclt_imgab "$t: started under B2 (LC_ALL=C, FV_ASCII, TERM=dumb, a config without a merged effect${lz:+; then its lazy data}): a hit, the state a normal load's under B2 [§10 env-diff]" \
                    "$id.b2" "$p" "$u" hit "${KCLT_IMG_B2[@]}" ${lz:+"RT_LAZY=$lz"} ;;
            bp) kclt_imgab "$t: started under B1 with its caller presets set before P loads: a hit, the state a normal load's [§10 env-diff, §7.7]" \
                    "$id.bp" "$p" "$u" hit "${KCLT_IMG_B1[@]/#RT_PRE=/RT_PREP=}" ;;
            key) if [[ $IMG_W == cr || $IMG_W == crbase || $IMG_W == rw ]]; then x=nowrite; else x=miss; fi
                kclt_imgab "$t: started with a KBOOL_CONFIG that adds a define (the merged config is keyed): a miss that writes another image, the state a normal load's [§7.1]" \
                    "$id.key" "$p" "$u" "$x" KBOOL_CONFIG="$KCLT_TMP/cfg1" ;;
            off) kclt_imgab "$t: started with KBOOL_IMAGE_CHAIN=off: a plain kk.uses (a prior set), the state a normal load's [§7.7]" \
                    "$id.off" "$p" "$u" "plain:KBOOL_IMAGE_CHAIN=off and unit " KBOOL_IMAGE_CHAIN=off ;;
            mode) if [[ $IMG_W == cr || $IMG_W == crbase || $IMG_W == rw ]]; then x=nowrite; else x=miss; fi
                kclt_imgab "$t: started with KBOOL_IMAGE_CHECK=hash (the effective check mode is keyed): a miss that writes another image, the state a normal load's [§7.6 IMG-D1]" \
                    "$id.mode" "$p" "$u" "$x" KBOOL_IMAGE_CHECK=hash ;;
            modex) kclt_imgab "$t: started with KBOOL_IMAGE_CHECK=bogus (an invalid value runs as the default mode: the same key): a hit, the state a normal load's [§3 IMG-D1]" \
                    "$id.modex" "$p" "$u" hit KBOOL_IMAGE_CHECK=bogus ;;
            vk) if [[ $IMG_W == cr || $IMG_W == crbase || $IMG_W == rw ]]; then x=nowriteq; else x=missq; fi
                kclt_imgab "$t: started with VERBOSE_KKLASS empty instead of debug (keyed): a miss that writes another image, the state a normal load's [§7.1]" \
                    "$id.vk" "$p" "$u" "$x" RT_VK= ;;
            clash|clashx)
                img=""
                while IFS= read -r x; do [[ $x == *"kbool: image: wrote "* ]] && img=${x#*wrote }; done < "$KCLT_TMP/d/$id.w.err"
                img=${img%% (*}
                v=""
                if [[ -f $img ]]; then
                    while IFS= read -r x; do
                        [[ $x == "declare -g "[A-Za-z_]*=* ]] || continue
                        x=${x#declare -g } x=${x%%=*}
                        [[ $x == KK* || $x == *[!A-Za-z0-9_]* ]] && continue
                        v=$x; break
                    done < "$img"
                fi
                if [[ -z $v ]]; then
                    kt_test_start "$t: a caller global named like an image scalar"
                    if [[ $IMG_W == cr || $IMG_W == crbase || $IMG_W == rw ]]; then kt_test_pass "ok (no image of this key)"; else kt_test_fail "no scalar found in '$img'"; fi
                    continue
                fi
                if [[ $c == clash ]]; then
                    kclt_imgab "$t: a caller global $v (a scalar the image creates) set before kk.image: a plain kk.uses (the image would write into it), nothing written, the state a normal load's [§8.1 I2a H1]" \
                        "$id.clash" "$p" "$u" "plain:'$v' exists in this shell already" "RT_PRE=$v=i3clash"
                else
                    kclt_imgab "$t: an exported preset $v (a scalar the image creates) in the environment: a plain kk.uses (the image would write into it), nothing written, the state a normal load's [§8.1 I2a H1]" \
                        "$id.clashx" "$p" "$u" "plain:'$v' exists in this shell already" "$v=i3clash"
                fi ;;
        esac
    done
}
