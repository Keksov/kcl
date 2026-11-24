#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%fv.views.sh}../../kbool.sh" || return
kk.unit fv.views || return $__kk_unit_rc

# fv.views — the view tree of the fv.* text UI (layer L2): Free Vision's TView
# and TGroup as kklass classes with FV's field names, the subview lists, FV
# corner bounds, GrowMode, and the "virtual elision" that runs a built-in
# virtual as a plain function unless the view's class overrides it. Port of
# FV views.inc (TView, TGroup); design: kcl/docs/dev/fv/P2_DESIGN.md (§1),
# API and deviations: README.md.
#
# P2 stage 2c-1: constants, TView / TGroup, the tree (insert, insertBefore,
# delete, makeFirst, putInFrontOf, first / last / next / prev / nextView /
# prevView), the bounds cache, GrowMode, locate / moveTo / growTo /
# changeBounds, makeLocal / makeGlobal / mouseInView, the elision
# (fv.views._virt) with its RESULT rule, reserved names and the constructor
# guard. Stage 2c-2: palettes and getColor, the drawing context and the
# writers, the painter (paint / drawView / over / drawUnder, the covering
# skip, shadows), show / hide, drawPart, redraw, both lock counters and the
# minimal TFrame; the redraw hook fv.views._changed draws. Stage 2c-3: the
# event dispatch (TGroup.HandleEvent's phases, positional events, broadcasts,
# FV's EventMask filter), message, the focus chain (select, setCurrent,
# focus, focusNext / selectNext, the virtual-aware setState with FV's side
# effects), command sets, resetCursor, the modal loop (Execute, execView,
# endModal, Valid; the EOF latch and the owner-process rule), mouseEvent and
# the basic TWindow (frame, title, number, palettes, window commands, Tab,
# cmClose, cmSelectWindowNum). Stage 2d: TWindow's Zoom / SizeLimits
# (MinWinSize) / CalcBounds (ZoomRect), cmZoom / cmResize, dragView (FV
# DragView: keyboard and mouse, motion coalescing, a resize ending a drag)
# and the frame's mouse (the close / zoom icons, dragging by the top row and
# the grow corner). P3 stage 3b (design P3_DESIGN.md §1-§3, §5): TScrollBar
# and TListViewer (FV views.inc, FPC 2025), standardScrollBar, ctrlToArrow,
# the tracking loops (fv.views._track). P3 stage 3c: the hot-key map of the
# pre / post scan (fv.views._hkLists, design §3.1, 10.3b).
#
# Conventions of every plain function here:
#   * the view name first; locals `__fvw_*`; fields read and written through
#     `${v}_data` (kklass friend contract, kklass book "Friend tables"), reads
#     as `${d[F]-}`;
#   * fork-free, set -eu clean; no `[[ == ]]` / `case` / `${x//}` between two
#     names (nocasematch would make `Win1` equal to `win1`): `[ "$a" = "$b" ]`
#     and `${a#"$b"}` are case-sensitive under it;
#   * procedures leave RESULT as it was (as kklass procs do); getters answer
#     in RESULT; a refused call is rc 1 (a value the caller may try) or rc 2
#     (not a view, a bad number, a bad argument count) with RESULT='' and a
#     kk.debug line. Programming errors that would corrupt the tree (a live
#     name re-created, a reserved name, a constructor that skipped
#     `inherited`) print one `Error:` line on stderr (silent only under
#     VERBOSE_KKLASS=quiet): the design's "fail loudly".

kk.uses kklass_pascal fv.video fv.drivers || return

# the settings hook (kkore kk.settings; kklass/docs/dev/IMAGE_PLAN.md §5):
# the kcl locale default, the public globals that keep a caller's value (each
# described where the state is listed below) and the owner process
fv.views._settings() {
    kk.localeDefault
    declare -g FV_MINWINSIZE_X=${FV_MINWINSIZE_X:-16} FV_MINWINSIZE_Y=${FV_MINWINSIZE_Y:-6}
    declare -g FV_DRAW_VIEW=${FV_DRAW_VIEW-} FV_DRAW_X=${FV_DRAW_X:-0} FV_DRAW_Y=${FV_DRAW_Y:-0} FV_DRAW_PAL=${FV_DRAW_PAL-}
    declare -g FV_CLIP_X1=${FV_CLIP_X1:-0} FV_CLIP_Y1=${FV_CLIP_Y1:-0} FV_CLIP_X2=${FV_CLIP_X2:-0} FV_CLIP_Y2=${FV_CLIP_Y2:-0}
    declare -g __FV_VW_OWNER=${__FV_VW_OWNER:-$BASHPID}
    declare -g FV_COMMANDSETCHANGED=${FV_COMMANDSETCHANGED:-0}
    declare -g FV_RECT_AX=${FV_RECT_AX:-0} FV_RECT_AY=${FV_RECT_AY:-0} FV_RECT_BX=${FV_RECT_BX:-0} FV_RECT_BY=${FV_RECT_BY:-0}
    declare -g FV_POINT_X=${FV_POINT_X:-0} FV_POINT_Y=${FV_POINT_Y:-0}
    declare -g FV_MIN_X=${FV_MIN_X:-0} FV_MIN_Y=${FV_MIN_Y:-0} FV_MAX_X=${FV_MAX_X:-0} FV_MAX_Y=${FV_MAX_Y:-0}
    return 0
}
kk.settings fv.views._settings LC_CTYPE FV_MINWINSIZE_X FV_MINWINSIZE_Y \
    FV_DRAW_VIEW FV_DRAW_X FV_DRAW_Y FV_DRAW_PAL FV_CLIP_X1 FV_CLIP_Y1 FV_CLIP_X2 FV_CLIP_Y2 \
    __FV_VW_OWNER FV_COMMANDSETCHANGED FV_RECT_AX FV_RECT_AY FV_RECT_BX FV_RECT_BY \
    FV_POINT_X FV_POINT_Y FV_MIN_X FV_MIN_Y FV_MAX_X FV_MAX_Y || return

# ---- constants (FV values; readonly once per process, kcl §1.10 rule 7) -----
# Naming: FV's identifier upper-cased behind a unit prefix: sfCursorVis ->
# FV_SF_CURSORVIS, ofTopSelect -> FV_OF_TOPSELECT, gfGrowLoX -> FV_GF_GROWLOX,
# dmLimitLoY -> FV_DM_LIMITLOY, hcNoContext -> FV_HC_NOCONTEXT. EventMask bits
# (FPC drivers.inc: evMouseDown $0001 ... evMouseWheel $0020) are FV_EM_*, so
# that they do not mix with the event record FV_EV_* of fv.drivers.
if [[ -z ${FV_SF_VISIBLE+x} || ${FV_SF_VISIBLE@a} != *r* ]]; then
    FV_SF_VISIBLE=$(( 0x1 )) FV_SF_CURSORVIS=$(( 0x2 )) FV_SF_CURSORINS=$(( 0x4 )) FV_SF_SHADOW=$(( 0x8 ))
    FV_SF_ACTIVE=$(( 0x10 )) FV_SF_SELECTED=$(( 0x20 )) FV_SF_FOCUSED=$(( 0x40 )) FV_SF_DRAGGING=$(( 0x80 ))
    FV_SF_DISABLED=$(( 0x100 )) FV_SF_MODAL=$(( 0x200 )) FV_SF_DEFAULT=$(( 0x400 )) FV_SF_EXPOSED=$(( 0x800 ))
    FV_OF_SELECTABLE=$(( 0x1 )) FV_OF_TOPSELECT=$(( 0x2 )) FV_OF_FIRSTCLICK=$(( 0x4 )) FV_OF_FRAMED=$(( 0x8 ))
    FV_OF_PREPROCESS=$(( 0x10 )) FV_OF_POSTPROCESS=$(( 0x20 )) FV_OF_BUFFERED=$(( 0x40 )) FV_OF_TILEABLE=$(( 0x80 ))
    FV_OF_CENTERX=$(( 0x100 )) FV_OF_CENTERY=$(( 0x200 )) FV_OF_CENTERED=$(( 0x300 )) FV_OF_VALIDATE=$(( 0x400 ))
    FV_GF_GROWLOX=$(( 0x1 )) FV_GF_GROWLOY=$(( 0x2 )) FV_GF_GROWHIX=$(( 0x4 )) FV_GF_GROWHIY=$(( 0x8 ))
    FV_GF_GROWALL=$(( 0xF )) FV_GF_GROWREL=$(( 0x10 ))
    FV_DM_DRAGMOVE=$(( 0x1 )) FV_DM_DRAGGROW=$(( 0x2 )) FV_DM_LIMITLOX=$(( 0x10 )) FV_DM_LIMITLOY=$(( 0x20 ))
    FV_DM_LIMITHIX=$(( 0x40 )) FV_DM_LIMITHIY=$(( 0x80 )) FV_DM_LIMITALL=$(( 0xF0 ))
    FV_HC_NOCONTEXT=0 FV_HC_DRAGGING=1
    FV_EM_MOUSEDOWN=$(( 0x1 )) FV_EM_MOUSEUP=$(( 0x2 )) FV_EM_MOUSEMOVE=$(( 0x4 )) FV_EM_MOUSEAUTO=$(( 0x8 ))
    FV_EM_KEYDOWN=$(( 0x10 )) FV_EM_MOUSEWHEEL=$(( 0x20 )) FV_EM_COMMAND=$(( 0x100 )) FV_EM_BROADCAST=$(( 0x200 ))
    FV_EM_MOUSE=$(( 0x2F )) FV_EM_KEYBOARD=$(( 0x10 )) FV_EM_MESSAGE=$(( 0xFF00 ))
    # FV MaxViewWidth (= fv.video's widest row) and high(Sw_Integer) (SizeLimits)
    __FV_VW_MAXW=1024 __FV_VW_HIGH=2147483647
    readonly FV_SF_VISIBLE FV_SF_CURSORVIS FV_SF_CURSORINS FV_SF_SHADOW FV_SF_ACTIVE FV_SF_SELECTED \
        FV_SF_FOCUSED FV_SF_DRAGGING FV_SF_DISABLED FV_SF_MODAL FV_SF_DEFAULT FV_SF_EXPOSED \
        FV_OF_SELECTABLE FV_OF_TOPSELECT FV_OF_FIRSTCLICK FV_OF_FRAMED FV_OF_PREPROCESS FV_OF_POSTPROCESS \
        FV_OF_BUFFERED FV_OF_TILEABLE FV_OF_CENTERX FV_OF_CENTERY FV_OF_CENTERED FV_OF_VALIDATE \
        FV_GF_GROWLOX FV_GF_GROWLOY FV_GF_GROWHIX FV_GF_GROWHIY FV_GF_GROWALL FV_GF_GROWREL \
        FV_DM_DRAGMOVE FV_DM_DRAGGROW FV_DM_LIMITLOX FV_DM_LIMITLOY FV_DM_LIMITHIX FV_DM_LIMITHIY FV_DM_LIMITALL \
        FV_HC_NOCONTEXT FV_HC_DRAGGING \
        FV_EM_MOUSEDOWN FV_EM_MOUSEUP FV_EM_MOUSEMOVE FV_EM_MOUSEAUTO FV_EM_KEYDOWN FV_EM_MOUSEWHEEL \
        FV_EM_COMMAND FV_EM_BROADCAST FV_EM_MOUSE FV_EM_KEYBOARD FV_EM_MESSAGE \
        __FV_VW_MAXW __FV_VW_HIGH
fi
# (stage 2c-2, its own guard: a process that loaded 2c-1 keeps the block above)
# TWindow Flags (wf), palettes (wp), wnNoNumber, TFrame FrameMode (fm)
if [[ -z ${FV_WF_MOVE+x} || ${FV_WF_MOVE@a} != *r* ]]; then
    FV_WF_MOVE=$(( 0x1 )) FV_WF_GROW=$(( 0x2 )) FV_WF_CLOSE=$(( 0x4 )) FV_WF_ZOOM=$(( 0x8 ))
    FV_WP_BLUEWINDOW=0 FV_WP_CYANWINDOW=1 FV_WP_GRAYWINDOW=2 FV_WN_NONUMBER=0
    FV_FM_CLOSECLICKED=$(( 0x1 )) FV_FM_ZOOMCLICKED=$(( 0x2 ))
    readonly FV_WF_MOVE FV_WF_GROW FV_WF_CLOSE FV_WF_ZOOM FV_WP_BLUEWINDOW FV_WP_CYANWINDOW \
        FV_WP_GRAYWINDOW FV_WN_NONUMBER FV_FM_CLOSECLICKED FV_FM_ZOOMCLICKED
fi
# (stage 2d) FV's MinWinSize, TWindow.SizeLimits' minimum: a typed constant
# FV programs may change, so a plain global (not 0-9 digits: FV's 16 x 6):
# FV_MINWINSIZE_X / _Y (the settings hook above)
# (P3 stage 3b) TScrollBar's part codes (FV sbLeftArrow .. sbIndicator) and
# StandardScrollBar's options (sbHorizontal, sbVertical, sbHandleKeyboard)
if [[ -z ${FV_SB_VERTICAL+x} || ${FV_SB_VERTICAL@a} != *r* ]]; then
    FV_SB_LEFTARROW=0 FV_SB_RIGHTARROW=1 FV_SB_PAGELEFT=2 FV_SB_PAGERIGHT=3 FV_SB_UPARROW=4
    FV_SB_DOWNARROW=5 FV_SB_PAGEUP=6 FV_SB_PAGEDOWN=7 FV_SB_INDICATOR=8
    FV_SB_HORIZONTAL=0 FV_SB_VERTICAL=1 FV_SB_HANDLEKEYBOARD=2
    readonly FV_SB_LEFTARROW FV_SB_RIGHTARROW FV_SB_PAGELEFT FV_SB_PAGERIGHT FV_SB_UPARROW \
        FV_SB_DOWNARROW FV_SB_PAGEUP FV_SB_PAGEDOWN FV_SB_INDICATOR \
        FV_SB_HORIZONTAL FV_SB_VERTICAL FV_SB_HANDLEKEYBOARD
fi

# ---- state ------------------------------------------------------------------
# Derived state keyed by the view name (design §1.2), kept across a reload:
#   AX AY        the absolute origin (screen cells)
#   C1 C2 C3 C4  the absolute clip X1 Y1 X2 Y2 (X2/Y2 exclusive) = the view's
#                rect ∩ its owner's clip; a view without an owner: its rect.
#                Empty when C1 == C3 or C2 == C4 (never C3 < C1)
#   LIVE         1 from TView's constructor to the destructor
#   GRP          1 for a group (TGroup's constructor); its subviews are the
#                instance array ${g}_views, back to front: the last element
#                is FV's First (the front)
# CRC: the rc of the last refused TView constructor (a subclass constructor
# returns it after `inherited`); RESNAME: the one reserved name the next
# constructor may take (fv.views._newReserved).
declare -gA __FV_VW_AX __FV_VW_AY __FV_VW_C1 __FV_VW_C2 __FV_VW_C3 __FV_VW_C4 __FV_VW_LIVE __FV_VW_GRP
declare -g __FV_VW_CRC=${__FV_VW_CRC:-0} __FV_VW_RESNAME=${__FV_VW_RESNAME-}
# Drawing state (stage 2c-2):
#   PAL[v]       v's palette resolved to fv.video symbols (design §1.9): a
#                string, entry i = ${PAL[v]:i-1:1}; filled on first use,
#                dropped for a subtree on insert / delete / resetPalette
#   FRM[f]       1 for a TFrame (the covering test of a framed group)
#   FK[f.s]      the frame's string cache, one slot s per state (0-3: active
#                + 2 dragging): FK the key of what it holds; FT/FTA, FM/FMA,
#                FB/FBA the top, body and bottom row (text / symbols), FS/FSA
#                the side column's character and symbol (border-only redraw)
#   LK[g]        g's user lock count (fv.views.lock), mirrored in LockFlag
# APAL: the root mapping, CAppColor's 127 entries as fv.video symbols (its
# default palette assigns 1-9 A-U to CAppColor's distinct bytes in order of
# first appearance, so the string follows by construction). A STUB until
# fv.app (P2 stage 2f): its setAppPalette changes this string and calls
# fv.views.resetPalette. ERRSYM: the symbol of FV's ErrorAttr (an index
# outside a palette); fv.video's default palette has no $CF, so it is the
# default symbol 0 until fv.app allocates one.
# LSU: the lockScreenUpdate count; LOCKN: the sum of the user lock counts;
# NODRAW: > 0 holds every redraw (bulk layout: ChangeBounds inside locate,
# a group resize's subview loop, fv.app's tile / cascade / resize);
# DEPTH: the nesting of drawing entries; UCLIP: the caller's fv.video clip
# saved by the outermost one; INGRP: 1 while a framework loop (not a Draw
# body) runs, so a finished paint need not restore the clip; P1..P4: the
# absolute rectangle the current paint may write; OIDX: a reordered view's
# old index (putInFrontOf -> the `order` redraw).
declare -gA __FV_VW_PAL __FV_VW_FRM __FV_VW_FK __FV_VW_FT __FV_VW_FTA __FV_VW_FM __FV_VW_FMA \
    __FV_VW_FB __FV_VW_FBA __FV_VW_FS __FV_VW_FSA __FV_VW_LK
declare -g __FV_VW_APAL=${__FV_VW_APAL:-123456789ABBC19DEFGGHIE2JKGG2JL2JKGG22JL5MN3O2PEH9NA5QBBPNHBGRB89A11C89C5MN3OSPEH2NK5TBBPNHBGRBDEFGGHPEH5MN3OP2JL9NA5UB12NL1GR1}
declare -g __FV_VW_ERRSYM=${__FV_VW_ERRSYM:-0}
declare -g __FV_VW_LSU=${__FV_VW_LSU:-0} __FV_VW_LOCKN=${__FV_VW_LOCKN:-0} __FV_VW_NODRAW=${__FV_VW_NODRAW:-0}
declare -g __FV_VW_DEPTH=${__FV_VW_DEPTH:-0} __FV_VW_UCLIP=${__FV_VW_UCLIP-} __FV_VW_INGRP=${__FV_VW_INGRP:-0}
declare -g __FV_VW_U1=${__FV_VW_U1:-0} __FV_VW_U2=${__FV_VW_U2:-0} __FV_VW_U3=${__FV_VW_U3:-0} __FV_VW_U4=${__FV_VW_U4:-0}
declare -g __FV_VW_P1=${__FV_VW_P1:-0} __FV_VW_P2=${__FV_VW_P2:-0} __FV_VW_P3=${__FV_VW_P3:-0} __FV_VW_P4=${__FV_VW_P4:-0}
declare -g __FV_VW_OIDX=${__FV_VW_OIDX:--1}
# INDRAW[v]: set while v's Draw runs (the paint stack; re-entrancy rule);
# WROW[y]: 1 for a screen row that holds or held wide cells, or that a
# wide character was written into (also one hidden at once: fv.video's
# WNEW; looked at by the edge test, fv.views._bands); FORCE: a forced
# update (redraw) waiting for the release; BANDED: the bands and widened
# rectangles the last fv.views._bands made
declare -gA __FV_VW_INDRAW
declare -ga __FV_VW_WROW
__FV_VW_INDRAW+=() __FV_VW_WROW+=()
declare -g __FV_VW_FORCE=${__FV_VW_FORCE:-0} __FV_VW_BANDED=${__FV_VW_BANDED:-0}
# D21 structure caches, rebuilt lazily. They hold the tree's SHAPE only (who
# owns whom, the order of each subview list), never a field's value: State,
# Options, the bounds and the absolute rects are read live on every use, so
# setState / show / hide, a bounds change and a field written through the
# friend contract need no invalidation. Dropped by fv.views._restruct:
#   DEX[v]  the arithmetic test "v and every owner visible, the root exposed"
#           over the LIVE State fields (fv.views._drawable's fast path; taken
#           only without a lock and without SKIP). Dropped at insert, delete
#           (_detach) and destruction (_free): an Owner changed
#   FRL[v]  the views in front of v or of an owner, innermost level first,
#           back to front within a level (fv.views._over / _uncover). Dropped
#           at insert, delete, destruction and putInFrontOf (an order change)
#   OEX[g]  the arithmetic test "a subview of g has ofPreProcess or
#           ofPostProcess" over the subviews' LIVE Options fields
#           (fv.views._groupEvent's pre / post scan). Dropped at insert,
#           delete and destruction: g's list changed (its order does not
#           matter to the test)
#   PNT[f]  a painter function drawPart has seen (its declare -F check);
#           never dropped: a painter unset after its first drawPart fails
#           with bash's "command not found" (rc 127) instead of rc 2
# Any code that edits ${g}_views or a view's Owner calls fv.views._restruct.
declare -gA __FV_VW_DEX __FV_VW_FRL __FV_VW_OEX __FV_VW_PNT
__FV_VW_DEX+=() __FV_VW_FRL+=() __FV_VW_OEX+=() __FV_VW_PNT+=()
# The drawing context of the Draw that runs (design §1.5; '' / 0 outside one):
# the view, its absolute origin, its resolved palette, and the part of it
# this paint may write in the view's own coordinates ([X1,X2) x [Y1,Y2)):
# FV_DRAW_VIEW / _X / _Y / _PAL, FV_CLIP_X1 / _Y1 / _X2 / _Y2 (the settings
# hook above).
# Events, focus, modal views (stage 2c-3):
#   PEND      1 when a terminal update was held back (lockScreenUpdate, a
#             user lock): the framework's own sequences flush at their end
#             only then (fv.views._release)
#   SKIP      a view the current framework sequence draws whole right after:
#             no redraw of it or inside it meanwhile (fv.views._drawable)
#   CPEND     a view whose tree waits for resetCursor at the end of the held
#             sequence (fv.views._cursorLater)
#   EH        the holds of the terminal update the modal loops keep while a
#             handler runs (one update per event: fv.views._showNow)
#   CMDOFF    the disabled commands (names; FV's CurCommandSet is the
#             complement), CMDINIT set once FV's default set was applied
#   TOPVIEW   FV's TheTopView: the view execView runs
#   GETEVENT  the event source of the modal loop and mouseEvent: a function
#             filling fv.drivers' FV_EV_* (rc 0, evNothing included; rc 1
#             at the end of input). fv.app (stage 2f) sets its _getEvent
#   PUTEVENT  FV's PutEvent (TWindow's modal cmClose posts cmCancel)
#   EOF       the end-of-input LATCH: once the event source said "end of
#             input", every running loop ends after the current event without
#             asking Valid and a new execView returns cmCancel at once.
#             Whoever starts a new input (fv.app's Init) resets it to 0
#   OWNER     the process that owns the screen (BASHPID when the unit was
#             loaded; fv.app's Init records its own): the modal loop refuses
#             to run anywhere else (inside $( ), a pipeline)
# FV_COMMANDSETCHANGED: FV's CommandSetChanged, 1 after a command set
# change; fv.app's Idle broadcasts cmCommandSetChanged and clears it.
# (OWNER and FV_COMMANDSETCHANGED: the settings hook above)
declare -g __FV_VW_PEND=${__FV_VW_PEND:-0} __FV_VW_SKIP=${__FV_VW_SKIP-} __FV_VW_TOPVIEW=${__FV_VW_TOPVIEW-}
declare -g __FV_VW_CPEND=${__FV_VW_CPEND-} __FV_VW_EH=${__FV_VW_EH:-0}
declare -g __FV_VW_GETEVENT=${__FV_VW_GETEVENT:-fv.drivers.getEvent} __FV_VW_PUTEVENT=${__FV_VW_PUTEVENT:-fv.drivers.putEvent}
declare -g __FV_VW_EOF=${__FV_VW_EOF:-0} __FV_VW_CMDINIT=${__FV_VW_CMDINIT-}
# RESIZES (stage 2f): the count of terminal resizes the event source handled
# itself (fv.app's GetEvent hands a cmResizeApp to the application at once and
# clears it, as FV's TProgram.GetEvent does with a system event): an inner
# loop that keeps geometry of its own (dragView) compares it around each read
declare -g __FV_VW_RESIZES=${__FV_VW_RESIZES:-0}
declare -gA __FV_VW_CMDOFF
if [[ -z $__FV_VW_CMDINIT ]]; then
    # FV: CurCommandSet = [0..255] - [cmZoom, cmClose, cmResize, cmNext, cmPrev]
    __FV_VW_CMDOFF=([cmZoom]=1 [cmClose]=1 [cmResize]=1 [cmNext]=1 [cmPrev]=1)
    __FV_VW_CMDINIT=1
fi
# The elision tables (design §1.4): IMPL = the plain body of each built-in
# virtual, keyed DEFININGCLASS.METHOD; FUNC = the virtuals FV declares as
# functions (they answer in RESULT on both paths; the others leave it).
# MERGED on a reload (+=), not reassigned: the framework units above this one
# (fv.menus, fv.app) add their classes' entries, which a re-source of this
# unit must keep.
declare -gA __FV_VW_IMPL __FV_VW_FUNC
# QGRP (stage 2f): built-in HandleEvent bodies of the units above this one
# that react to no broadcast and pass one on as TGroup's does (fv.app's
# TDesktop / TProgram / TApplication): fv.views._quiet walks into them as into
# TGroup's. Merged on a reload, like IMPL
declare -gA __FV_VW_QGRP
__FV_VW_QGRP+=()
# BCAST (stage 3a-2, the broadcast table): the broadcasts each built-in
# HandleEvent body reacts to, BCAST[BODY]="cmA cmB ..." ('' = none). The
# dispatch and fv.views._quiet skip, without a call, a view whose handler is
# a body with a row that does not list the command (a group: when its
# subtree has no listener either); a body without a row (and a user
# override, always) gets every broadcast its EventMask lets through. A QGRP
# entry counts as the row ''. Merged on a reload, like IMPL: the units above
# this one add the rows of their bodies
declare -gA __FV_VW_BCAST
__FV_VW_BCAST+=(
    [fv.views._viewEvent]='' [fv.views._frameEvent]='' [fv.views._groupEvent]=''
    [fv.views._windowEvent]='cmSelectWindowNum'
    [fv.views._sbEvent]='' [fv.views._lvEvent]='cmScrollBarChanged cmScrollBarClicked'
)
# (P3 stage 3b) the lists and scroll bars:
#   SB[b]    1 for a live TScrollBar (the list's bar fields are used only
#            while they name one)
#   LY[v]    FV's TListViewer.LastY (the SizeY its bar's steps were set for)
#   QX       the list that moves its own vertical bar right now (P3-4, L7:
#            only a list whose HandleEvent is the built-in): the
#            cmScrollBarChanged broadcast of that bar (FV_EV_INFO its
#            VScrollBar) skips it (fv.views._quiet, the
#            dispatch), so nothing walks back to it; '' otherwise
#   TRK      1 when a tracking loop's next read must end it (fv.views._track:
#            a release or a key met while draining moves; cleared when a
#            bar's or a list's tracking starts: a loop that returned early
#            may have left it set)
#   FOK[f]   a formatter function seen (its declare -F check, as PNT)
#   AT[s]    symbol s repeated MAXW times (a row's attributes: a slice)
#   C2A      FV's CtrlToArrow table (fv.views.ctrlToArrow)
declare -gA __FV_VW_SB __FV_VW_LY __FV_VW_FOK __FV_VW_AT
__FV_VW_SB+=() __FV_VW_LY+=() __FV_VW_FOK+=() __FV_VW_AT+=()
declare -g __FV_VW_QX=${__FV_VW_QX-} __FV_VW_TRK=${__FV_VW_TRK-} __FV_VW_PAD=''
# (P3 stage 3c) the HOT-KEY MAP (design §3.1, 10.3b): the pre / post scan of
# a focused event skips, without a call, a view whose built-in handler only
# reacts to its hot keys there (fv.dialogs' TButton, TLabel, TCluster) when
# the key names none of them and the view is not focused.
#   HKS[BODY]  the units above register, per built-in HandleEvent body with
#              hot-key-only pre / post work, where its hot texts live: the
#              suffix of a variable after the view's name — `_data[Title]`
#              (one text) or `_items[@]` (an array, one text per element).
#              Merged on a reload, like IMPL
#   HOT[G:K]   the map: K = a folded hot letter (FV's ~K~, any script), the
#              value " v1  v2 " = the views of group G with that hot letter
#   HKG[G]     1 when G's map is built and holds a view, 0 built and empty
#   HKR[v]     a mapped view's text reference (the full variable name) and
#   HKT[v]     the stamp it was mapped from (the text; an array's elements
#              @Q-quoted): a skipped view whose text differs (a direct write
#              of the field) makes the map rebuilt on that key
#   HKE[BODY]  optional, registered like HKS for an array body: the item
#              test `FN V I` (rc 0 = V's text I can react: TCluster's
#              EnableMask bit), asked before a typed match counts
#   HKI[v:K]   the index of v's first text with the hot letter K, and
#   HKF[v]     v's item test (its body's HKE), for a body with one
#   HKK[BODY]  optional (P3 3h), registered like HKS: the key names
#              (FV_EV_KEY, not Alt keys or kbChar) that name a view of that
#              body although it has no hot letter — fv.dialogs' THistory,
#              opened by kbDown / kbCtrlX while its link is focused; the map
#              holds them as HOT[G:#KEY] (merged on a reload, like HKS)
#   HKP        the pass of the key being dispatched (typed / base / ''), so
#              the widgets' fv.views._hk asks fv.views.hotKeyIs in the same
#              pass the map decided (a typed match wins over a base match).
#              Each TGroup.HandleEvent holds its own as a LOCAL of
#              fv.views._groupEvent (a nested group's dispatch, a modal loop
#              inside a handler, gets its own; bash's dynamic scope gives
#              the outer one back on return); the global stays ''. Only a
#              mapped view asks in it (another one asks without a pass)
#   HKN        (a LOCAL too) the group whose dispatch runs: a subgroup it
#              dispatches to keeps its pass typed (asks no base key) when
#              that owner decided typed — a typed match anywhere wins
# The map is a structure cache: dropped with OEX by fv.views._restruct (an
# insert, a delete, a destruction) and by fv.views._hkDirty (the setters).
declare -gA __FV_VW_HKS __FV_VW_HOT __FV_VW_HKG __FV_VW_HKR __FV_VW_HKT __FV_VW_HKE __FV_VW_HKI __FV_VW_HKF __FV_VW_HKK
__FV_VW_HKS+=() __FV_VW_HOT+=() __FV_VW_HKG+=() __FV_VW_HKR+=() __FV_VW_HKT+=() __FV_VW_HKE+=() __FV_VW_HKI+=() __FV_VW_HKF+=() __FV_VW_HKK+=()
declare -g __FV_VW_HKP='' __FV_VW_HKN=''
printf -v __FV_VW_PAD '%*s' "$__FV_VW_MAXW" ''
declare -gA __FV_VW_C2A=(
    [kbCtrlS]=kbLeft [kbCtrlD]=kbRight [kbCtrlE]=kbUp [kbCtrlX]=kbDown [kbCtrlA]=kbHome [kbCtrlF]=kbEnd
    [kbCtrlG]=kbDel [kbCtrlV]=kbIns [kbCtrlR]=kbPgUp [kbCtrlC]=kbPgDn [kbCtrlH]=kbBack
)
__FV_VW_IMPL+=(
    [TView.ChangeBounds]=fv.views._viewChangeBounds [TView.CalcBounds]=fv.views._viewCalcBounds
    [TView.SizeLimits]=fv.views._viewSizeLimits [TView.GetHelpCtx]=fv.views._viewGetHelpCtx
    [TGroup.ChangeBounds]=fv.views._groupChangeBounds [TGroup.GetHelpCtx]=fv.views._groupGetHelpCtx
    [TView.Draw]=fv.views._viewDraw [TGroup.Draw]=fv.views._groupDraw [TFrame.Draw]=fv.views._frameDraw
    [TView.GetPalette]=fv.views._viewGetPalette [TFrame.GetPalette]=fv.views._frameGetPalette
    [TView.HandleEvent]=fv.views._viewEvent [TGroup.HandleEvent]=fv.views._groupEvent
    [TView.SetState]=fv.views._viewSetState [TGroup.SetState]=fv.views._groupSetState
    [TView.Valid]=fv.views._viewValid [TGroup.Valid]=fv.views._groupValid
    [TView.Execute]=fv.views._viewExecute [TGroup.Execute]=fv.views._groupExecute
    [TView.EndModal]=fv.views._viewEndModal [TGroup.EndModal]=fv.views._groupEndModal
    [TWindow.HandleEvent]=fv.views._windowEvent [TWindow.SetState]=fv.views._windowSetState
    [TWindow.GetPalette]=fv.views._windowGetPalette [TWindow.GetTitle]=fv.views._windowGetTitle
    [TWindow.InitFrame]=fv.views._windowInitFrame [TWindow.Close]=fv.views._windowClose
    [TFrame.HandleEvent]=fv.views._frameEvent [TWindow.SizeLimits]=fv.views._windowSizeLimits
    [TWindow.CalcBounds]=fv.views._windowCalcBounds [TWindow.Zoom]=fv.views._windowZoom
    [TScrollBar.Draw]=fv.views._sbDraw [TScrollBar.GetPalette]=fv.views._sbGetPalette
    [TScrollBar.HandleEvent]=fv.views._sbEvent [TScrollBar.ScrollStep]=fv.views._sbScrollStep
    [TScrollBar.ScrollDraw]=fv.views._sbScrollDraw
    [TListViewer.Draw]=fv.views._lvDraw [TListViewer.GetPalette]=fv.views._lvGetPalette
    [TListViewer.HandleEvent]=fv.views._lvEvent [TListViewer.SetState]=fv.views._lvSetState
    [TListViewer.ChangeBounds]=fv.views._lvChangeBounds [TListViewer.FocusItem]=fv.views._lvFocusItem
    [TListViewer.SelectItem]=fv.views._lvSelectItem [TListViewer.IsSelected]=fv.views._lvIsSelected
)
__FV_VW_FUNC+=(
    [GetPalette]=1 [GetHelpCtx]=1 [Valid]=1 [Execute]=1 [GetTitle]=1 [Hint]=1 [GetEvent]=1
    [ScrollStep]=1 [IsSelected]=1
)
# The event-name -> EventMask bit lookup (used by the dispatch, stage 2c-3).
declare -gA __FV_VW_EVBIT=(
    [evMouseDown]=1 [evMouseUp]=2 [evMouseMove]=4 [evMouseAuto]=8 [evKeyDown]=16
    [evMouseWheel]=32 [evCommand]=256 [evBroadcast]=512
)
# The var parameters of FV's geometry procedures (TRect Bounds, TPoint, the
# Min / Max of SizeLimits): procedures leave RESULT alone, so these are the
# answer of CalcBounds and SizeLimits (both paths), and getBounds /
# getExtent / makeLocal / makeGlobal set them besides RESULT: FV_RECT_AX /
# _AY / _BX / _BY, FV_POINT_X / _Y, FV_MIN_X / _Y, FV_MAX_X / _Y (the
# settings hook above).

# ---- classes (FV views.inc; fields design §1.2, virtuals §1.3) --------------
# Each built-in virtual's kklass body is one line calling its plain body, so
# a user override reaches it with `inherited NAME "$@"` (a bare `inherited`
# in a method forwards no arguments). The thin aliases (D16: MakeFirst,
# PutInFrontOf, Locate, MoveTo, GrowTo, Insert, InsertBefore) are for set-up
# code; the framework calls the plain functions. No `Delete` alias: removal
# is `fv.views.delete G V`, destruction `V.delete`.
class TView
    public
        var Owner
        var OriginX
        var OriginY
        var SizeX
        var SizeY
        var CursorX
        var CursorY
        var State
        var Options
        var EventMask
        var GrowMode
        var DragMode
        var HelpCtx
        constructor Create
        nofields destructor Done
        nofields proc ChangeBounds
        nofields proc CalcBounds
        nofields proc SizeLimits
        nofields func GetHelpCtx
        nofields proc Draw
        nofields func GetPalette
        nofields proc MakeFirst
        nofields proc PutInFrontOf
        nofields proc Locate
        nofields proc MoveTo
        nofields proc GrowTo
        nofields proc DrawView
        nofields proc Show
        nofields proc Hide
        nofields proc HandleEvent
        nofields proc SetState
        nofields func Valid
        nofields func Execute
        nofields proc EndModal
        nofields proc Select
end
# TView.new NAME AX AY BX BY — FV `Init(R)` with `R.Assign(AX, AY, BX, BY)`
# (corners, B exclusive). rc 1: NAME is a live view (the tree is repaired,
# one Error line); rc 2: a reserved name (`__fv` inside) or a bound that is
# not an integer (one Error line).
TView.Create() { fv.views._create "$this" "$@" || return; }
TView.Done() { fv.views._done "$this" || return; }
TView.ChangeBounds() { fv.views._viewChangeBounds "$this" "$@" || return; }
TView.CalcBounds() { fv.views._viewCalcBounds "$this" "$@" || return; }
TView.SizeLimits() { fv.views._viewSizeLimits "$this" "$@" || return; }
TView.GetHelpCtx() { fv.views._viewGetHelpCtx "$this" "$@" || return; }
TView.MakeFirst() { fv.views.makeFirst "$this" || return; }
TView.PutInFrontOf() { fv.views.putInFrontOf "$this" "$@" || return; }
TView.Locate() { fv.views.locate "$this" "$@" || return; }
TView.MoveTo() { fv.views.moveTo "$this" "$@" || return; }
TView.GrowTo() { fv.views.growTo "$this" "$@" || return; }
TView.Draw() { fv.views._viewDraw "$this" || return; }
TView.GetPalette() { fv.views._viewGetPalette "$this" || return; }
TView.DrawView() { fv.views.drawView "$this" || return; }
TView.Show() { fv.views.show "$this" || return; }
TView.Hide() { fv.views.hide "$this" || return; }
TView.HandleEvent() { fv.views._viewEvent "$this" "$@" || return; }
TView.SetState() { fv.views._viewSetState "$this" "$@" || return; }
TView.Valid() { fv.views._viewValid "$this" "$@" || return; }
TView.Execute() { fv.views._viewExecute "$this" "$@" || return; }
TView.EndModal() { fv.views._viewEndModal "$this" "$@" || return; }
TView.Select() { fv.views.select "$this" || return; }
build TView

class TGroup : TView
    public
        var Current
        var Phase
        var EndState
        var LockFlag
        constructor Create
        nofields override proc ChangeBounds
        nofields override func GetHelpCtx
        nofields override proc Draw
        nofields override proc HandleEvent
        nofields override proc SetState
        nofields override func Valid
        nofields override func Execute
        nofields override proc EndModal
        nofields proc Insert
        nofields proc InsertBefore
        nofields proc Lock
        nofields proc Unlock
        nofields proc SelectNext
        nofields func ExecView
end
# TGroup.new NAME AX AY BX BY — FV TGroup.Init: TView's, then ofSelectable +
# ofBuffered, EventMask $FFFF, an empty subview list. A refused TView part
# returns its rc (the group part does not run).
TGroup.Create() {
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.views._groupCreate "$this"
}
TGroup.ChangeBounds() { fv.views._groupChangeBounds "$this" "$@" || return; }
TGroup.GetHelpCtx() { fv.views._groupGetHelpCtx "$this" "$@" || return; }
TGroup.Insert() { fv.views.insert "$this" "$@" || return; }
TGroup.InsertBefore() { fv.views.insertBefore "$this" "$@" || return; }
TGroup.Draw() { fv.views._groupDraw "$this" || return; }
TGroup.Lock() { fv.views.lock "$this" || return; }
TGroup.Unlock() { fv.views.unlock "$this" || return; }
TGroup.HandleEvent() { fv.views._groupEvent "$this" "$@" || return; }
TGroup.SetState() { fv.views._groupSetState "$this" "$@" || return; }
TGroup.Valid() { fv.views._groupValid "$this" "$@" || return; }
TGroup.Execute() { fv.views._groupExecute "$this" "$@" || return; }
TGroup.EndModal() { fv.views._groupEndModal "$this" "$@" || return; }
TGroup.SelectNext() { fv.views.selectNext "$this" "$@" || return; }
TGroup.ExecView() { fv.views.execView "$this" "$@" || return; }
build TGroup

# TFrame.new NAME AX AY BX BY — FV TFrame.Init: TView's, then GrowMode
# gfGrowHiX + gfGrowHiY, EventMask + evBroadcast, FrameMode 0. It draws the
# FV look of its owner (a TWindow from stage 2c-3; any group): double line
# when sfActive, single when not, the owner's title centred, `[■]` (wfClose)
# and `[↑]` / `↕` (wfZoom) while active, the window number (1..9), the grow
# corner (wfGrow, active), in CFrame's colours through the owner's palette.
# The owner fields read: Flags, Number, Title (or its GetTitle, a func, when
# its class has one). Stage 2d: HandleEvent, the mouse on the frame (the
# close and zoom icons, a double click on the top row, dragging the owner by
# the top row or the grow corner).
class TFrame : TView
    public
        var FrameMode
        constructor Create
        nofields override proc Draw
        nofields override func GetPalette
        nofields override proc HandleEvent
end
TFrame.Create() {
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.views._frameCreate "$this"
}
TFrame.Draw() { fv.views._frameDraw "$this" || return; }
TFrame.GetPalette() { fv.views._frameGetPalette "$this" || return; }
TFrame.HandleEvent() { fv.views._frameEvent "$this" "$@" || return; }
build TFrame

# TWindow.new NAME AX AY BX BY [TITLE [NUMBER]] — FV TWindow.Init(Bounds,
# ATitle, ANumber): TGroup's, then sfShadow, ofSelectable + ofTopSelect,
# GrowMode gfGrowAll + gfGrowRel, Flags wfMove + wfGrow + wfClose + wfZoom,
# Palette wpBlueWindow, Frame by InitFrame (virtual; the built-in makes the
# TFrame NAME__fvframe over the whole window) inserted, ZoomRect = the
# bounds ("AX AY BX BY"). NUMBER: 1..9 is shown on the frame (FV wnNoNumber
# 0; not an integer: 0). Stage 2d: Zoom, SizeLimits (MinWinSize) and
# CalcBounds (the ZoomRect follows an owner resize), cmZoom / cmResize.
class TWindow : TGroup
    public
        var Flags
        var Title
        var Number
        var Palette
        var Frame
        var ZoomRect
        constructor Create
        nofields override proc HandleEvent
        nofields override proc SetState
        nofields override func GetPalette
        nofields override proc SizeLimits
        nofields override proc CalcBounds
        nofields func GetTitle
        nofields proc InitFrame
        nofields proc Close
        nofields proc Zoom
end
TWindow.Create() {
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.views._windowCreate "$this" "${5-}" "${6-}"
}
TWindow.HandleEvent() { fv.views._windowEvent "$this" "$@" || return; }
TWindow.SetState() { fv.views._windowSetState "$this" "$@" || return; }
TWindow.GetPalette() { fv.views._windowGetPalette "$this" || return; }
TWindow.GetTitle() { fv.views._windowGetTitle "$this" "$@" || return; }
TWindow.InitFrame() { fv.views._windowInitFrame "$this" || return; }
TWindow.Close() { fv.views._windowClose "$this" || return; }
TWindow.SizeLimits() { fv.views._windowSizeLimits "$this" "$@" || return; }
TWindow.CalcBounds() { fv.views._windowCalcBounds "$this" "$@" || return; }
TWindow.Zoom() { fv.views._windowZoom "$this" || return; }
build TWindow

# (P3 stage 3b) TScrollBar.new NAME AX AY BX BY — FV TScrollBar.Init(Bounds):
# TView's, then EventMask + evMouseWheel, Value Min Max 0, PgStep ArStep 1,
# Id 0 (no cmIdCommunicate); vertical when 1 wide (GrowMode gfGrowLoX +
# gfGrowHiX + gfGrowHiY), else horizontal (gfGrowLoY + gfGrowHiX + gfGrowHiY).
# The glyphs come from the screen's mode (design P3 §2.7). Set the numbers
# with fv.views.scrollBarSet (FV SetParams / SetValue / SetRange / SetStep)
class TScrollBar : TView
    public
        var Value
        var Min
        var Max
        var PgStep
        var ArStep
        var Id
        constructor Create
        nofields override proc Draw
        nofields override func GetPalette
        nofields override proc HandleEvent
        nofields func ScrollStep
        nofields proc ScrollDraw
end
TScrollBar.Create() {
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.views._sbCreate "$this"
}
TScrollBar.Draw() { fv.views._sbDraw "$this" || return; }
TScrollBar.GetPalette() { fv.views._sbGetPalette "$this" || return; }
TScrollBar.HandleEvent() { fv.views._sbEvent "$this" "$@" || return; }
TScrollBar.ScrollStep() { fv.views._sbScrollStep "$this" "$@" || return; }
TScrollBar.ScrollDraw() { fv.views._sbScrollDraw "$this" || return; }
build TScrollBar

# (P3 stage 3b) TListViewer.new NAME AX AY BX BY [NUMCOLS [HSCROLLBAR
# [VSCROLLBAR]]] — FV TListViewer.Init(Bounds, ANumCols, AHScrollBar,
# AVScrollBar): TView's, then ofFirstClick + ofSelectable, EventMask +
# evBroadcast + evMouseWheel, NUMCOLS columns (default 1), the bars ('' =
# none; a horizontal one gets SetStep(SizeX div NumCols, 1)), TopItem
# Focused Range 0. FV's abstract GetText is the data model of design P3 §5:
# List = the name of an indexed array, Formatter = an optional plain
# function `FMT INDEX WIDTH` -> RESULT, Marks = the name of an array whose
# set entries (not '' or 0) show their items selected (D26). Refused before
# anything is made (rc 2, one Error line; .delete the bare instance): a
# NUMCOLS that is not 1..1024, a bar that is not a live TScrollBar
class TListViewer : TView
    public
        var NumCols
        var TopItem
        var Focused
        var Range
        var HScrollBar
        var VScrollBar
        var List
        var Formatter
        var Marks
        constructor Create
        nofields override proc Draw
        nofields override func GetPalette
        nofields override proc HandleEvent
        nofields override proc SetState
        nofields override proc ChangeBounds
        nofields proc FocusItem
        nofields proc SelectItem
        nofields func IsSelected
end
TListViewer.Create() {
    fv.views._lvArgs "$this" "${@:5}" || return
    inherited
    [[ -n ${__FV_VW_LIVE[$this]-} ]] || return "$__FV_VW_CRC"
    fv.views._lvCreate "$this" "${5:-1}" "${6-}" "${7-}"
}
TListViewer.Draw() { fv.views._lvDraw "$this" || return; }
TListViewer.GetPalette() { fv.views._lvGetPalette "$this" || return; }
TListViewer.HandleEvent() { fv.views._lvEvent "$this" "$@" || return; }
TListViewer.SetState() { fv.views._lvSetState "$this" "$@" || return; }
TListViewer.ChangeBounds() { fv.views._lvChangeBounds "$this" "$@" || return; }
TListViewer.FocusItem() { fv.views._lvFocusItem "$this" "$@" || return; }
TListViewer.SelectItem() { fv.views._lvSelectItem "$this" "$@" || return; }
TListViewer.IsSelected() { fv.views._lvIsSelected "$this" "$@" || return; }
build TListViewer

# ---- the hooks ------------------------------------------------------------------
# fv.views._changed WHY V G AX1 AY1 AX2 AY2 — the REDRAW HOOK. Called after
# the tree or a view's place changed: G is V's owner ('' for a view without
# one; for `delete` the group V was removed from) and the rectangle
# (absolute, B exclusive, not clipped, no shadow) the screen area concerned.
# Nothing is drawn for an invisible V (a V whose State is unset, as in the
# constructor guard's repair, counts as visible); the rectangle is widened by
# FV's ShadowSize (2, 1) when V has sfShadow. WHY and the redraw:
#   insert  fv.views.insert / insertBefore: V's rect (FV InsertBefore ->
#           Show) -> drawView V (V, its shadow, the views in front over it)
#   delete  fv.views.delete, V.delete, the constructor guard's repair: V's
#           rect before the removal (FV Hide -> DrawHide) -> drawUnder G
#   order   putInFrontOf / makeFirst of a visible V: V's rect -> moved to
#           the front past a view that overlapped it: drawView V; moved
#           back past one: the views now in front of it over S(V); else
#           nothing (FV PutInFrontOf's LastView test)
#   bounds  TView / TGroup ChangeBounds: V's old rect ∪ its new rect (FV
#           ChangeBounds -> DrawView / Redraw) -> drawUnder G (a view without
#           an owner: drawView V); a group with a size change calls it once,
#           after its subviews' own `bounds` calls, which run under NODRAW
#   move    locate / moveTo / growTo, after ChangeBounds (which ran under
#           NODRAW): old ∪ new (FV Locate -> DrawUnderRect) -> drawUnder G
# So one place change draws S(A) ∪ S(B) once, in z-order. RESULT is kept.
fv.views._changed() {
    local __fvw_rs0=${RESULT-} __fvw_st=$FV_SF_VISIBLE __fvw_x2=$6 __fvw_y2=$7
    if [[ -n ${__FV_VW_LIVE[$2]-} ]]; then
        local -n __fvw_cd=${2}_data
        __fvw_st=${__fvw_cd[State]-$FV_SF_VISIBLE}
    fi
    if (( ! (__fvw_st & FV_SF_VISIBLE) )); then return 0; fi
    if (( __fvw_st & FV_SF_SHADOW )); then __fvw_x2=$(( __fvw_x2 + 2 )) __fvw_y2=$(( __fvw_y2 + 1 )); fi
    if [ "$1" = insert ]; then fv.views._drawView "$2"
    elif [ "$1" = order ]; then fv.views._order "$2" "$3"
    elif [[ -n $3 ]]; then fv.views._drawUnder "$3" "$4" "$5" "$__fvw_x2" "$__fvw_y2"
    elif ! [ "$1" = delete ]; then fv.views._drawView "$2"; fi
    RESULT=$__fvw_rs0
    return 0
}

# fv.views._order V G — the `order` redraw after putInFrontOf (V's old index
# in __FV_VW_OIDX; fv.views._orderHit): V moved in front of views that
# covered part of it (their S() met V's rect) -> drawView V (whole: a
# partial repaint would need V's own focus redraws too, and a list writes
# its rows anyway); moved in front of views that only its shadow meets ->
# only the shadow; moved behind views whose S() meets S(V) -> those views
# over S(V); else nothing
fv.views._order() {
    local __fvw_m=0 __fvw_q1 __fvw_q2 __fvw_q3 __fvw_q4
    fv.views._orderHit "$1" "$2"
    if (( __fvw_m == 1 )); then fv.views._drawView "$1"
    elif (( __fvw_m == 3 )); then
        local -n __fvw_od=${1}_data
        local __fvw_x=${__FV_VW_AX[$1]} __fvw_y=${__FV_VW_AY[$1]} __fvw_w=${__fvw_od[SizeX]:-0} __fvw_h=${__fvw_od[SizeY]:-0}
        # (the two shadow strips: right of V from its second row, below V from its third column)
        local -a __fvw_rs=() __fvw_q=(
            "$(( __fvw_x + __fvw_w ))" "$(( __fvw_y + 1 ))" "$(( __fvw_x + __fvw_w + 2 ))" "$(( __fvw_y + __fvw_h + 1 ))"
            "$(( __fvw_x + 2 ))" "$(( __fvw_y + __fvw_h ))" "$(( __fvw_x + __fvw_w ))" "$(( __fvw_y + __fvw_h + 1 ))")
        # (D21: each strip cut to the owner's clip, where the shadow is shaded; an empty one dropped)
        local __fvw_j __fvw_1 __fvw_2 __fvw_3 __fvw_4
        for (( __fvw_j = 0; __fvw_j < 8; __fvw_j += 4 )); do
            __fvw_1=${__fvw_q[__fvw_j]} __fvw_2=${__fvw_q[__fvw_j+1]} __fvw_3=${__fvw_q[__fvw_j+2]} __fvw_4=${__fvw_q[__fvw_j+3]}
            if (( __fvw_1 < __FV_VW_C1[$2] )); then __fvw_1=${__FV_VW_C1[$2]}; fi
            if (( __fvw_2 < __FV_VW_C2[$2] )); then __fvw_2=${__FV_VW_C2[$2]}; fi
            if (( __fvw_3 > __FV_VW_C3[$2] )); then __fvw_3=${__FV_VW_C3[$2]}; fi
            if (( __fvw_4 > __FV_VW_C4[$2] )); then __fvw_4=${__FV_VW_C4[$2]}; fi
            if (( __fvw_1 < __fvw_3 && __fvw_2 < __fvw_4 )); then __fvw_rs+=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4"); fi
        done
        if (( ${#__fvw_rs[@]} )); then fv.views._drawRects "$1"; fi
    elif (( __fvw_m == 2 )); then fv.views._overOnly "$1" "$__fvw_q1" "$__fvw_q2" "$__fvw_q3" "$__fvw_q4"; fi
}
# fv.views._orderHit V G — after V moved from the old index __FV_VW_OIDX,
# the caller's __fvw_m: moved in front of visible views — 1 when the S() of
# one of them meets V's rect (V was covered there), else 3 when only V's
# shadow meets one; moved behind them — 2 when S(V) meets the S() of one;
# else 0. __fvw_q1..4 = S(V)
fv.views._orderHit() {
    local -n __fvw_l=${2}_views __fvw_hd=${1}_data
    local __fvw_i=-1 __fvw_j=$__FV_VW_OIDX __fvw_a __fvw_b __fvw_k __fvw_x2 __fvw_y2
    local __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
    __fvw_m=0
    fv.views._idx "$2" "$1"
    if (( __fvw_i < 0 || __fvw_j < 0 || __fvw_i == __fvw_j )); then return 0; fi
    fv.views._srect "$1"
    __fvw_q1=$__fvw_r1 __fvw_q2=$__fvw_r2 __fvw_q3=$__fvw_r3 __fvw_q4=$__fvw_r4
    # (V's own rect, without the shadow)
    __fvw_x2=$(( __fvw_q1 + ${__fvw_hd[SizeX]:-0} )) __fvw_y2=$(( __fvw_q2 + ${__fvw_hd[SizeY]:-0} ))
    if (( __fvw_i > __fvw_j )); then __fvw_a=$__fvw_j __fvw_b=$(( __fvw_i - 1 )); else __fvw_a=$(( __fvw_i + 1 )) __fvw_b=$__fvw_j; fi
    for (( ; __fvw_a <= __fvw_b; __fvw_a++ )); do
        __fvw_k=${__fvw_l[__fvw_a]}
        local -n __fvw_kd=${__fvw_k}_data
        if (( ! (${__fvw_kd[State]:-0} & FV_SF_VISIBLE) )); then continue; fi
        fv.views._srect "$__fvw_k"
        if (( __fvw_r1 >= __fvw_q3 || __fvw_q1 >= __fvw_r3 || __fvw_r2 >= __fvw_q4 || __fvw_q2 >= __fvw_r4 )); then continue; fi
        if (( __fvw_i < __fvw_j )); then __fvw_m=2; return 0; fi
        if (( __fvw_r1 < __fvw_x2 && __fvw_q1 < __fvw_r3 && __fvw_r2 < __fvw_y2 && __fvw_q2 < __fvw_r4 )); then __fvw_m=1; return 0; fi
        __fvw_m=3
    done
}

# fv.views._drawRects V — V painted within each rectangle of the caller's
# __fvw_rs (absolute X1 Y1 X2 Y2, ...) with its shadow there, then the views
# in front of V over them, flush (the `order` redraw's shadow-only form)
fv.views._drawRects() {
    fv.views._drawable "$1" || return 0
    local __fvw_bg __fvw_b1 __fvw_b2 __fvw_b3 __fvw_b4 __fvw_j
    if (( ${#__FV_VW_INDRAW[@]} )); then fv.views._nestCut "$1"; fi
    if (( ${#__FV_VW_WROW[@]} )); then fv.views._bands; fi
    fv.views._begin
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        fv.views._paint "$1" "${__fvw_rs[@]:__fvw_j:4}"
        fv.views._shade "$1" "${__fvw_rs[@]:__fvw_j:4}" || :
    done
    fv.views._over "$1"
    if (( ${#__FV_VW_WROW[@]} || ${#__FV_VS_WNEW[@]} )) || [[ ${__FV_VS_WIDE[*]-} == *[123]* ]]; then fv.views._wideMark; fi
    fv.views._end
    fv.views._flush
}

# fv.views._setCurrent G V [MODE] — the FOCUS HOOK, FV SetCurrent(V, Mode):
# G's Current becomes V ('' = none). When G is focused the old Current loses
# sfFocused, then (MODE not `enter`) the old Current loses sfSelected, (MODE
# not `leave`) V gains sfSelected, and V gains sfFocused when G is focused;
# then Current := V. MODE: '' (FV NormalSelect), enter / leave (EnterSelect
# / LeaveSelect: execView). Every bit goes through the virtual-aware
# setState (FV's side effects: the focus broadcasts, TWindow's sfActive and
# its frame's border, the window commands). D17: no Lock of G (FV redraws
# all of G at its Unlock); the terminal update is held to the end. RESULT
# is kept.
fv.views._setCurrent() {
    local -n __fvw_g=${1}_data
    local __fvw_o=${__fvw_g[Current]-} __fvw_m=${3-} __fvw_f __fvw_rr=${RESULT-}
    if [ "$__fvw_o" = "$2" ]; then return 0; fi
    if [[ -n $__fvw_o && -z ${__FV_VW_LIVE[$__fvw_o]-} ]]; then __fvw_o=''; fi
    __fvw_f=$(( ${__fvw_g[State]:-0} & FV_SF_FOCUSED ))
    __FV_VW_LSU=$(( __FV_VW_LSU + 1 ))
    if [[ -n $__fvw_o ]]; then
        if (( __fvw_f )); then fv.views._virt "$__fvw_o" SetState "$FV_SF_FOCUSED" 0 || :; fi
        if ! [ "$__fvw_m" = enter ]; then fv.views._virt "$__fvw_o" SetState "$FV_SF_SELECTED" 0 || :; fi
    fi
    if [[ -n $2 && -n ${__FV_VW_LIVE[$2]-} ]]; then
        if ! [ "$__fvw_m" = leave ]; then fv.views._virt "$2" SetState "$FV_SF_SELECTED" 1 || :; fi
        if (( __fvw_f )); then fv.views._virt "$2" SetState "$FV_SF_FOCUSED" 1 || :; fi
    fi
    # (G itself may have been destroyed by a handler of the broadcasts)
    if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then __fvw_g[Current]=$2; fi
    fv.views._release
    RESULT=$__fvw_rr
}

# ---- the elision (design §1.4) ----------------------------------------------
# fv.views._virt V METHOD ARGS — call V's METHOD as FV would call a virtual:
# the plain body directly when the method's defining class (the kklass owner
# table, read on every call: no cache) is a built-in one, a kklass dispatch
# (user code) otherwise. The RESULT / rc rule, the same on both paths for
# every body form (kklass round 7, K-2 — before it, an explicit `return 0`
# lost a func's RESULT and a failing last command lost its rc):
#   * a proc leaves the caller's RESULT; its rc is the body's;
#   * a FUNC answers with what RESULT holds when its body ends with rc 0,
#     however it ends (falls off the end, `return 0`, a last `inherited`);
#     it fails with the body's rc (N != 0), which leaves the caller's RESULT.
# The plain path: a FUNC with rc 0 answers, a FUNC with rc != 0 and every
# proc leave the caller's RESULT.
fv.views._virt() {
    local __fvw_c=${1}_class __fvw_f __fvw_r=${RESULT-} __fvw_s=0
    # (one simple command: the assignments run in order)
    __fvw_f="${!__fvw_c-}_class_method_owner[$2]" __fvw_f=${__FV_VW_IMPL[${!__fvw_f-}.$2]-}
    # ("${@:3}" on the hottest path: a caller IFS holding \x01, bash's
    # internal quoting byte, garbles that expansion — unsupported, README)
    if [[ -z $__fvw_f ]]; then "$1.$2" "${@:3}"; return; fi
    "$__fvw_f" "$1" "${@:3}" || __fvw_s=$?
    if [[ -z ${__FV_VW_FUNC[$2]-} ]] || (( __fvw_s )); then RESULT=$__fvw_r; fi
    return "$__fvw_s"
}

# ---- private helpers ----------------------------------------------------------
# fv.views._err MSG — one `Error: fv.views: MSG` line on stderr unless
# VERBOSE_KKLASS=quiet (the loud refusals, see the header)
fv.views._err() {
    if [[ ${VERBOSE_KKLASS-} != quiet ]]; then printf 'Error: fv.views: %s\n' "$1" >&2; fi
    return 0
}

# fv.views._bad CALLER MSG — a malformed call: RESULT='', one debug line,
# rc 2 (`if …; then fv.views._bad insert 'wrong argument count'; return; fi`)
fv.views._bad() {
    RESULT=''
    kk.debug "Error: fv.views.$1: $2"
    return 2
}

# fv.views._ints VALUE... — each VALUE an integer (an optional '-', 1-9
# digits, leading zeros decimal) -> the caller's array __fvw_v; rc 1 at the
# first that is not
fv.views._ints() {
    local __fvw_a __fvw_s
    __fvw_v=()
    for __fvw_a; do
        __fvw_s=${__fvw_a#-}
        if [[ -z $__fvw_s || $__fvw_s == *[!0123456789]* || ${#__fvw_s} -gt 9 ]]; then return 1; fi
        if [[ $__fvw_a == -* ]]; then __fvw_v+=("$(( -10#$__fvw_s ))"); else __fvw_v+=("$(( 10#$__fvw_s ))"); fi
    done
}

# fv.views._view V / fv.views._group G — rc 0 for a live view / group; else
# rc 2, RESULT='' and a debug line; a kklass instance that is not a live
# view is a loud error (one Error line): its constructor skipped
# `inherited`, or it was re-created over a live name. A destroyed view is no
# kklass instance any more (`.delete` removed its tables): a debug line only.
fv.views._view() {
    if [[ -n $1 && -n ${__FV_VW_LIVE[$1]-} ]]; then return 0; fi
    RESULT=''
    fv.views._dead "$1" "$2"
    return 2
}
fv.views._group() {
    if [[ -n $1 && -n ${__FV_VW_GRP[$1]-} && -n ${__FV_VW_LIVE[$1]-} ]]; then return 0; fi
    RESULT=''
    if [[ -n $1 && -n ${__FV_VW_LIVE[$1]-} ]]; then kk.debug "Error: fv.views.$2: '$1' is not a group"
    else fv.views._dead "$1" "$2"; fi
    return 2
}
fv.views._dead() {   # NAME CALLER
    local __fvw_n=$1
    # an identifier that names a kklass instance (its class variable is set)
    if [[ -n $__fvw_n && $__fvw_n != *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]* \
          && $__fvw_n != [0123456789]* ]]; then
        __fvw_n=${__fvw_n}_class
        if [[ -n ${!__fvw_n-} ]]; then
            __fvw_n="${1}_data[State]"
            if [[ -z ${!__fvw_n+x} ]]; then
                fv.views._err "$2: '$1' is not a live view: its constructor did not call inherited (TView.Create)"
            else
                fv.views._err "$2: '$1' is not a live view (re-created over a live name)"
            fi
            return 0
        fi
    fi
    kk.debug "Error: fv.views.$2: '$1' is not a view"
}

# fv.views._idx G V — __fvw_i (the caller's) = V's index in ${G}_views, -1
# when it is not there
fv.views._idx() {
    local -n __fvw_l=${1}_views
    for (( __fvw_i = ${#__fvw_l[@]} - 1; __fvw_i >= 0; __fvw_i-- )); do
        if [ "${__fvw_l[__fvw_i]}" = "$2" ]; then return 0; fi
    done
}

# fv.views._restruct [order] — drop the D21 structure caches (see the state
# block): after any edit of a subview list or an Owner; `order` (a list
# reordered, every Owner the same) drops only what depends on the order
fv.views._restruct() {
    __FV_VW_FRL=()
    if [[ -z ${1-} ]]; then __FV_VW_DEX=() __FV_VW_OEX=() __FV_VW_HOT=() __FV_VW_HKG=() __FV_VW_HKR=() __FV_VW_HKT=() __FV_VW_HKI=() __FV_VW_HKF=(); fi
}

# fv.views._calc V [ONLY] — the absolute origin and clip of V and its
# subtree (ONLY 1: of V alone; its subviews keep their old cache)
fv.views._calc() {
    local -n __fvw_d=${1}_data
    local __fvw_o=${__fvw_d[Owner]-} __fvw_x __fvw_y __fvw_w __fvw_h __fvw_1 __fvw_2 __fvw_3 __fvw_4 __fvw_k
    __fvw_x=${__fvw_d[OriginX]:-0} __fvw_y=${__fvw_d[OriginY]:-0}
    __fvw_w=${__fvw_d[SizeX]:-0} __fvw_h=${__fvw_d[SizeY]:-0}
    if [[ -n $__fvw_o ]]; then
        __fvw_x=$(( __fvw_x + __FV_VW_AX[$__fvw_o] )) __fvw_y=$(( __fvw_y + __FV_VW_AY[$__fvw_o] ))
        __fvw_1=${__FV_VW_C1[$__fvw_o]} __fvw_2=${__FV_VW_C2[$__fvw_o]}
        __fvw_3=${__FV_VW_C3[$__fvw_o]} __fvw_4=${__FV_VW_C4[$__fvw_o]}
        if (( __fvw_x > __fvw_1 )); then __fvw_1=$__fvw_x; fi
        if (( __fvw_y > __fvw_2 )); then __fvw_2=$__fvw_y; fi
        if (( __fvw_x + __fvw_w < __fvw_3 )); then __fvw_3=$(( __fvw_x + __fvw_w )); fi
        if (( __fvw_y + __fvw_h < __fvw_4 )); then __fvw_4=$(( __fvw_y + __fvw_h )); fi
    else
        __fvw_1=$__fvw_x __fvw_2=$__fvw_y __fvw_3=$(( __fvw_x + __fvw_w )) __fvw_4=$(( __fvw_y + __fvw_h ))
    fi
    if (( __fvw_3 < __fvw_1 )); then __fvw_3=$__fvw_1; fi
    if (( __fvw_4 < __fvw_2 )); then __fvw_4=$__fvw_2; fi
    __FV_VW_AX[$1]=$__fvw_x __FV_VW_AY[$1]=$__fvw_y
    __FV_VW_C1[$1]=$__fvw_1 __FV_VW_C2[$1]=$__fvw_2 __FV_VW_C3[$1]=$__fvw_3 __FV_VW_C4[$1]=$__fvw_4
    if [[ -n ${__FV_VW_GRP[$1]-} && ${2-} != 1 ]]; then
        local -n __fvw_l=${1}_views
        for __fvw_k in "${__fvw_l[@]}"; do fv.views._calc "$__fvw_k"; done
    fi
}

# fv.views._setBounds V AX AY BX BY [ONLY] — FV SetBounds (the width capped
# at MaxViewWidth) + the bounds cache of V's subtree (ONLY 1: of V alone)
fv.views._setBounds() {
    local -n __fvw_d=${1}_data
    local __fvw_w=$(( $4 - $2 ))
    if (( __fvw_w > __FV_VW_MAXW )); then __fvw_w=$__FV_VW_MAXW; fi
    __fvw_d[OriginX]=$2 __fvw_d[OriginY]=$3 __fvw_d[SizeX]=$__fvw_w __fvw_d[SizeY]=$(( $5 - $3 ))
    fv.views._calc "$1" "${6-}"
}

# fv.views._abs V — __fvw_r1..4 (the caller's): V's absolute rect
fv.views._abs() {
    local -n __fvw_d=${1}_data
    __fvw_r1=${__FV_VW_AX[$1]} __fvw_r2=${__FV_VW_AY[$1]}
    __fvw_r3=$(( __fvw_r1 + ${__fvw_d[SizeX]:-0} )) __fvw_r4=$(( __fvw_r2 + ${__fvw_d[SizeY]:-0} ))
}

# fv.views._resetCurrent G — FV ResetCurrent: Current := the front-most
# visible selectable subview (FirstMatch(sfVisible, ofSelectable)), else none
fv.views._resetCurrent() {
    local -n __fvw_l=${1}_views
    local __fvw_i __fvw_k
    for (( __fvw_i = ${#__fvw_l[@]} - 1; __fvw_i >= 0; __fvw_i-- )); do
        __fvw_k=${__fvw_l[__fvw_i]}
        local -n __fvw_kd=${__fvw_k}_data
        if (( (${__fvw_kd[State]:-0} & FV_SF_VISIBLE) && (${__fvw_kd[Options]:-0} & FV_OF_SELECTABLE) )); then
            fv.views._setCurrent "$1" "$__fvw_k"
            return 0
        fi
    done
    fv.views._setCurrent "$1" ''
}

# fv.views._detach G V I — remove V (at index I) from G's list, Owner = '',
# Current reset as FV's Delete does (Hide -> ResetCurrent for a visible
# selectable V; and whenever V was Current), V's subtree cache made
# root-relative
fv.views._detach() {
    local -n __fvw_l=${1}_views __fvw_d=${2}_data __fvw_g=${1}_data
    local __fvw_st=${__fvw_d[State]:-0} __fvw_ix=$3
    # (as FV's Delete: V hidden first, then ResetCurrent while V is still in
    # G, so a focused V loses its focus with its owner set (cmReleasedFocus
    # reaches G) and nothing of V is redrawn meanwhile; its bit back after)
    if (( (__fvw_st & FV_SF_VISIBLE) && (${__fvw_d[Options]:-0} & FV_OF_SELECTABLE) )) \
       || [ "${__fvw_g[Current]-}" = "$2" ]; then
        __fvw_d[State]=$(( __fvw_st & ~FV_SF_VISIBLE ))
        fv.views._resetCurrent "$1"
        if [[ -n ${__FV_VW_LIVE[$2]-} ]]; then
            __fvw_d[State]=$(( (${__fvw_d[State]:-0} & ~FV_SF_VISIBLE) | (__fvw_st & FV_SF_VISIBLE) ))
        fi
        # (a handler of the focus broadcasts may have reordered G)
        local __fvw_i=-1
        fv.views._idx "$1" "$2"
        __fvw_ix=$__fvw_i
    fi
    if (( __fvw_ix >= 0 )); then __fvw_l=("${__fvw_l[@]:0:$__fvw_ix}" "${__fvw_l[@]:$__fvw_ix+1}"); fi
    fv.views._restruct
    if [[ -z ${__FV_VW_LIVE[$2]-} ]]; then return 0; fi
    __fvw_d[Owner]=''
    fv.views._calc "$2"
    fv.views._palReset "$2"
}

# fv.views._free V — the destruction of V's own part: a group's subviews
# are destroyed (front to back, each with Owner cleared first, so that none
# goes through a per-view removal), its list freed; the private entries go
fv.views._free() {
    local __fvw_k
    if [[ -n ${__FV_VW_GRP[$1]-} ]]; then
        # (FV TGroup.Done hides each subview first: its Current loses the
        # focus and the selection, so a window's commands are disabled
        # again; nothing is drawn, the group is going away)
        local -n __fvw_fg=${1}_data
        if [[ -n ${__fvw_fg[Current]-} ]]; then
            __FV_VW_NODRAW=$(( __FV_VW_NODRAW + 1 ))
            fv.views._setCurrent "$1" ''
            __FV_VW_NODRAW=$(( __FV_VW_NODRAW - 1 ))
        fi
        local -n __fvw_l=${1}_views
        local -a __fvw_kids=("${__fvw_l[@]}")
        __fvw_l=()
        fv.views._restruct
        for (( __fvw_k = ${#__fvw_kids[@]} - 1; __fvw_k >= 0; __fvw_k-- )); do
            if [[ -n ${__FV_VW_LIVE[${__fvw_kids[__fvw_k]}]-} ]]; then
                local -n __fvw_kd=${__fvw_kids[__fvw_k]}_data
                __fvw_kd[Owner]=''
            fi
            if declare -F "${__fvw_kids[__fvw_k]}.delete" >/dev/null; then "${__fvw_kids[__fvw_k]}.delete"; fi
        done
        unset "${1}_views" '__FV_VW_GRP[$1]'
    fi
    # a group destroyed while locked no longer holds the flush; when nothing
    # holds it any more, what was drawn meanwhile (its removal) is sent now
    if [[ -n ${__FV_VW_LK[$1]-} ]]; then
        __FV_VW_LOCKN=$(( __FV_VW_LOCKN - ${__FV_VW_LK[$1]} ))
        if (( __FV_VW_LOCKN < 0 )); then __FV_VW_LOCKN=0; fi
        if (( __FV_VW_LOCKN == 0 )); then
            local __fvw_rr=${RESULT-}
            fv.views._flush
            RESULT=$__fvw_rr
        fi
    fi
    # a frame's string cache: one slot per state (fv.views._frameRows)
    if [[ -n ${__FV_VW_FRM[$1]-} ]]; then
        for __fvw_k in 0 1 2 3; do
            unset "__FV_VW_FK[$1.$__fvw_k]" "__FV_VW_FT[$1.$__fvw_k]" "__FV_VW_FTA[$1.$__fvw_k]" \
                "__FV_VW_FM[$1.$__fvw_k]" "__FV_VW_FMA[$1.$__fvw_k]" "__FV_VW_FB[$1.$__fvw_k]" \
                "__FV_VW_FBA[$1.$__fvw_k]" "__FV_VW_FS[$1.$__fvw_k]" "__FV_VW_FSA[$1.$__fvw_k]"
        done
    fi
    unset '__FV_VW_LIVE[$1]' '__FV_VW_AX[$1]' '__FV_VW_AY[$1]' \
        '__FV_VW_C1[$1]' '__FV_VW_C2[$1]' '__FV_VW_C3[$1]' '__FV_VW_C4[$1]' \
        '__FV_VW_PAL[$1]' '__FV_VW_FRM[$1]' '__FV_VW_LK[$1]' '__FV_VW_SB[$1]' '__FV_VW_LY[$1]'
    # (the name may come back as a new view: nothing of this one's shape stays)
    fv.views._restruct
}

# ---- construction, destruction, reserved names (design §1.6) ----------------
fv.views._create() {   # V AX AY BX BY
    local __fvw_n=$1 __fvw_g __fvw_i
    local -a __fvw_v
    shift
    # a reserved name (`__fv` inside: framework-made views) only through
    # fv.views._newReserved
    if [[ ${__fvw_n#*__fv} != "$__fvw_n" ]] && ! [ "$__fvw_n" = "$__FV_VW_RESNAME" ]; then
        fv.views._err "TView.Create: '$__fvw_n': names with '__fv' are reserved for framework-made views"
        __FV_VW_CRC=2
        return 2
    fi
    __FV_VW_RESNAME=''
    # the constructor guard: kklass re-creates a live instance without its
    # destructor; repair the tree (the stale name out of its owner's list,
    # its old subviews destroyed, its entries freed) and refuse
    if [[ -n ${__FV_VW_LIVE[$__fvw_n]-} ]]; then
        for __fvw_g in "${!__FV_VW_GRP[@]}"; do
            fv.views._idx "$__fvw_g" "$__fvw_n"
            if (( __fvw_i >= 0 )); then
                local __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
                fv.views._abs "$__fvw_n"
                fv.views._detach "$__fvw_g" "$__fvw_n" "$__fvw_i"
                fv.views._changed delete "$__fvw_n" "$__fvw_g" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
                break
            fi
        done
        local -n __fvw_d=${__fvw_n}_data
        __fvw_d[Owner]=''
        fv.views._free "$__fvw_n"
        fv.views._err "TView.Create: '$__fvw_n' is a live view: re-creating it is refused (delete it first: $__fvw_n.delete); its old tree was removed"
        __FV_VW_CRC=1
        return 1
    fi
    if (( $# < 4 )) || ! fv.views._ints "$1" "$2" "$3" "$4"; then
        fv.views._err "TView.Create: '$__fvw_n': the bounds must be four integers AX AY BX BY (got: $*)"
        __FV_VW_CRC=2
        return 2
    fi
    local -n __fvw_d=${__fvw_n}_data
    __fvw_d[Owner]='' __fvw_d[CursorX]=0 __fvw_d[CursorY]=0 __fvw_d[State]=$FV_SF_VISIBLE __fvw_d[Options]=0
    __fvw_d[EventMask]=$(( FV_EM_MOUSEDOWN | FV_EM_KEYDOWN | FV_EM_COMMAND ))
    __fvw_d[GrowMode]=0 __fvw_d[DragMode]=$FV_DM_LIMITLOY __fvw_d[HelpCtx]=$FV_HC_NOCONTEXT
    __FV_VW_LIVE[$__fvw_n]=1
    fv.views._setBounds "$__fvw_n" "${__fvw_v[@]}"
}

fv.views._groupCreate() {   # G
    local -n __fvw_d=${1}_data
    __fvw_d[Options]=$(( ${__fvw_d[Options]:-0} | FV_OF_SELECTABLE | FV_OF_BUFFERED ))
    __fvw_d[EventMask]=$(( 0xFFFF ))
    __fvw_d[Current]='' __fvw_d[Phase]=phFocused __fvw_d[EndState]='' __fvw_d[LockFlag]=0
    declare -ga "${1}_views=()"
    __FV_VW_GRP[$1]=1
}

# V.delete (FV Done): V out of its owner first (one `delete` redraw of its
# area), then a group's subviews destroyed, then V's entries freed. A name
# that is not live (refused or repaired by the guard) has nothing to undo.
fv.views._done() {   # V
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    local -n __fvw_d=${1}_data
    local __fvw_o=${__fvw_d[Owner]-} __fvw_i=-1 __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
    if [[ -n $__fvw_o && -n ${__FV_VW_GRP[$__fvw_o]-} ]]; then
        fv.views._idx "$__fvw_o" "$1"
        if (( __fvw_i >= 0 )); then
            fv.views._abs "$1"
            fv.views._detach "$__fvw_o" "$1" "$__fvw_i"
            fv.views._changed delete "$1" "$__fvw_o" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
        fi
    fi
    fv.views._free "$1"
}

# fv.views._newReserved OWNER ROLE CLASS ARGS... — the framework's way to make
# a view with the reserved name ${OWNER}__fv${ROLE} (win1__fvframe,
# app__fvdesktop): CLASS.new under that name; RESULT = the name. ROLE:
# letters and digits. rc: the constructor's (2 for a bad ROLE).
fv.views._newReserved() {
    if [[ -z ${2-} || $2 == *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789]* ]] || (( $# < 3 )); then
        fv.views._bad _newReserved 'OWNER ROLE CLASS ARGS (ROLE: letters and digits)'; return
    fi
    local __fvw_n=${1}__fv$2 __fvw_s=0
    __FV_VW_RESNAME=$__fvw_n
    "$3.new" "$__fvw_n" "${@:4}" || __fvw_s=$?
    __FV_VW_RESNAME=''
    RESULT=$__fvw_n
    return "$__fvw_s"
}

# fv.views.isView V — rc 0 when V is a live view (constructed through
# TView.Create and not destroyed or re-created since); for a constructor of
# yours: `inherited; fv.views.isView "$this" || return 1`
fv.views.isView() {
    [[ -n ${1-} && -n ${__FV_VW_LIVE[$1]-} ]]
}

# ---- the tree (FV TGroup.Insert / InsertBefore / Delete, TView.MakeFirst /
# PutInFrontOf / Next / Prev / NextView / PrevView, TGroup.First / Last) ------

# fv.views.insert G V — FV Insert: V in front of every subview of G
fv.views.insert() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" insert || return
    local -n __fvw_l=${1}_views
    local __fvw_t=''
    if (( ${#__fvw_l[@]} )); then __fvw_t=${__fvw_l[-1]}; fi
    fv.views._insert "$1" "$2" "$__fvw_t" insert
}

# fv.views.insertBefore G V TARGET — FV InsertBefore: V directly in front of
# TARGET (a subview of G); TARGET '' = behind every subview (FV Target = nil)
fv.views.insertBefore() {
    if (( $# != 3 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" insertBefore || return
    fv.views._insert "$1" "$2" "$3" insertBefore
}

fv.views._insert() {   # G V TARGET CALLER
    local __fvw_i=-1 __fvw_p __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
    fv.views._view "$2" "$4" || return
    local -n __fvw_d=${2}_data __fvw_gd=${1}_data __fvw_l=${1}_views
    if [[ -n ${__fvw_d[Owner]-} ]]; then
        RESULT=''; kk.debug "Error: fv.views.$4: '$2' is already in '${__fvw_d[Owner]}'"; return 1
    fi
    # no cycle: V is neither G nor an owner of G
    __fvw_p=$1
    while [[ -n $__fvw_p ]]; do
        if [ "$__fvw_p" = "$2" ]; then RESULT=''; kk.debug "Error: fv.views.$4: '$2' would own itself"; return 1; fi
        local -n __fvw_pd=${__fvw_p}_data
        __fvw_p=${__fvw_pd[Owner]-}
    done
    if [[ -n $3 ]]; then
        fv.views._idx "$1" "$3"
        if (( __fvw_i < 0 )); then RESULT=''; kk.debug "Error: fv.views.$4: '$3' is not a subview of '$1'"; return 1; fi
    fi
    # FV InsertBefore: centring by ofCenterX / ofCenterY (FV `div`: toward 0)
    if (( ${__fvw_d[Options]:-0} & FV_OF_CENTERX )); then
        __fvw_d[OriginX]=$(( (${__fvw_gd[SizeX]:-0} - ${__fvw_d[SizeX]:-0}) / 2 ))
    fi
    if (( ${__fvw_d[Options]:-0} & FV_OF_CENTERY )); then
        __fvw_d[OriginY]=$(( (${__fvw_gd[SizeY]:-0} - ${__fvw_d[SizeY]:-0}) / 2 ))
    fi
    __fvw_l=("${__fvw_l[@]:0:$__fvw_i+1}" "$2" "${__fvw_l[@]:$__fvw_i+1}")
    __fvw_d[Owner]=$1
    fv.views._restruct
    fv.views._calc "$2"
    fv.views._palReset "$2"
    local __fvw_rr=${RESULT-} __fvw_sk=$__FV_VW_SKIP
    __FV_VW_LSU=$(( __FV_VW_LSU + 1 ))
    # FV InsertBefore: a group with sfActive passes it to V (V is drawn whole
    # below, so nothing of V is drawn for that state change: SKIP; what the
    # state change shows outside V is drawn, P3 3b: a list's scroll bar);
    # FV: Show -> SetState(sfVisible) -> Owner^.ResetCurrent for a selectable
    # V (V's own redraws held the same way: the old Current's are not)
    if (( ${__fvw_gd[State]:-0} & FV_SF_ACTIVE )); then
        __FV_VW_SKIP=$2
        fv.views._virt "$2" SetState "$FV_SF_ACTIVE" 1 || :
        __FV_VW_SKIP=$__fvw_sk
    fi
    if (( (${__fvw_d[State]:-0} & FV_SF_VISIBLE) && (${__fvw_d[Options]:-0} & FV_OF_SELECTABLE) )); then
        __FV_VW_SKIP=$2
        fv.views._resetCurrent "$1"
        __FV_VW_SKIP=$__fvw_sk
    fi
    if [[ -n ${__FV_VW_LIVE[$2]-} ]]; then
        fv.views._abs "$2"
        fv.views._changed insert "$2" "$1" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
    fi
    fv.views._release
    RESULT=$__fvw_rr
}

# fv.views.delete G V — FV Delete: V out of G (its Owner '', Current reset
# as FV does, V keeps its State); V stays a live view that may be inserted
# again. Destroying it is V.delete.
fv.views.delete() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" delete || return
    fv.views._view "$2" delete || return
    local __fvw_i=-1 __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
    fv.views._idx "$1" "$2"
    if (( __fvw_i < 0 )); then RESULT=''; kk.debug "Error: fv.views.delete: '$2' is not a subview of '$1'"; return 1; fi
    fv.views._abs "$2"
    fv.views._detach "$1" "$2" "$__fvw_i"
    fv.views._changed delete "$2" "$1" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
}

# fv.views.putInFrontOf V TARGET — FV PutInFrontOf: V directly in front of
# TARGET (a sibling; '' = behind all). A no-op without an owner, for TARGET =
# V or when V already is directly in front of TARGET. A visible V: the
# `order` redraw and, when V is selectable, FV's ResetCurrent.
fv.views.putInFrontOf() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" putInFrontOf || return
    local -n __fvw_d=${1}_data
    local __fvw_g=${__fvw_d[Owner]-} __fvw_i=-1 __fvw_j __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
    [[ -n $__fvw_g ]] || return 0
    if [ "$2" = "$1" ]; then return 0; fi
    local -n __fvw_l=${__fvw_g}_views
    fv.views._idx "$__fvw_g" "$1"
    __fvw_j=$__fvw_i
    if [[ -n $2 ]]; then
        fv.views._idx "$__fvw_g" "$2"
        if (( __fvw_i < 0 )); then RESULT=''; kk.debug "Error: fv.views.putInFrontOf: '$2' is not a sibling of '$1'"; return 1; fi
        # TARGET = V's NextView (the view directly behind V)
        if (( __fvw_i == __fvw_j - 1 )); then return 0; fi
    elif (( __fvw_j == 0 )); then
        return 0
    fi
    __fvw_l=("${__fvw_l[@]:0:$__fvw_j}" "${__fvw_l[@]:$__fvw_j+1}")
    __fvw_i=-1
    if [[ -n $2 ]]; then fv.views._idx "$__fvw_g" "$2"; fi
    __fvw_l=("${__fvw_l[@]:0:$__fvw_i+1}" "$1" "${__fvw_l[@]:$__fvw_i+1}")
    fv.views._restruct order
    if (( ${__fvw_d[State]:-0} & FV_SF_VISIBLE )); then
        local __fvw_rr=${RESULT-} __fvw_sk=$__FV_VW_SKIP __fvw_m=0 __fvw_q1 __fvw_q2 __fvw_q3 __fvw_q4
        __FV_VW_LSU=$(( __FV_VW_LSU + 1 ))
        if (( ${__fvw_d[Options]:-0} & FV_OF_SELECTABLE )); then
            # (V moved in front of views that covered part of it is drawn
            # whole by the `order` redraw below: its focus redraws are left out)
            __FV_VW_OIDX=$__fvw_j
            fv.views._orderHit "$1" "$__fvw_g"
            if (( __fvw_m == 1 )); then __FV_VW_SKIP=$1; fi
            fv.views._resetCurrent "$__fvw_g"
            __FV_VW_SKIP=$__fvw_sk
        fi
        if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then
            fv.views._abs "$1"
            __FV_VW_OIDX=$__fvw_j
            fv.views._changed order "$1" "$__fvw_g" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
        fi
        __FV_VW_OIDX=-1
        fv.views._release
        RESULT=$__fvw_rr
    fi
}

# fv.views.makeFirst V — FV MakeFirst: V in front of its siblings
fv.views.makeFirst() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" makeFirst || return
    local -n __fvw_d=${1}_data
    local __fvw_g=${__fvw_d[Owner]-}
    [[ -n $__fvw_g ]] || return 0
    local -n __fvw_l=${__fvw_g}_views
    fv.views.putInFrontOf "$1" "${__fvw_l[-1]}"
}

# navigation: RESULT = the view, rc 1 and RESULT='' for FV's nil
# first G (FV First: the front), last G (FV Last: the back)
fv.views.first() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" first || return
    local -n __fvw_l=${1}_views
    if (( ${#__fvw_l[@]} )); then RESULT=${__fvw_l[-1]}; return 0; fi
    RESULT=''
    return 1
}
fv.views.last() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" last || return
    local -n __fvw_l=${1}_views
    if (( ${#__fvw_l[@]} )); then RESULT=${__fvw_l[0]}; return 0; fi
    RESULT=''
    return 1
}
# next V (FV Next: the view behind V; the back one's Next is the front one,
# a ring), prev V (FV Prev: the view in front of V; the front one's Prev is
# the back one), nextView / prevView (FV NextView / PrevView: nil at the
# end instead of the wrap). A view without an owner: nil.
fv.views.next() { fv.views._step "${1-}" -1 1 next "$#"; }
fv.views.prev() { fv.views._step "${1-}" 1 1 prev "$#"; }
fv.views.nextView() { fv.views._step "${1-}" -1 0 nextView "$#"; }
fv.views.prevView() { fv.views._step "${1-}" 1 0 prevView "$#"; }
fv.views._step() {   # V DIR WRAP CALLER ARGC
    if (( $5 != 1 )); then fv.views._bad "${FUNCNAME[1]#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" "$4" || return
    local -n __fvw_d=${1}_data
    local __fvw_g=${__fvw_d[Owner]-} __fvw_i=-1 __fvw_n
    RESULT=''
    [[ -n $__fvw_g ]] || return 1
    local -n __fvw_l=${__fvw_g}_views
    fv.views._idx "$__fvw_g" "$1"
    __fvw_n=${#__fvw_l[@]}
    __fvw_i=$(( __fvw_i + $2 ))
    if (( __fvw_i < 0 || __fvw_i >= __fvw_n )); then
        (( $3 )) || return 1
        __fvw_i=$(( (__fvw_i + __fvw_n) % __fvw_n ))
    fi
    RESULT=${__fvw_l[__fvw_i]}
}

# ---- geometry (FV GetBounds, GetExtent, Locate, MoveTo, GrowTo, MakeLocal,
# MakeGlobal, MouseInView; ChangeBounds, CalcBounds, SizeLimits) ---------------

# fv.views.getBounds V — RESULT="AX AY BX BY" (owner-relative corners, B
# exclusive) and FV_RECT_AX/_AY/_BX/_BY
fv.views.getBounds() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" getBounds || return
    local -n __fvw_d=${1}_data
    FV_RECT_AX=${__fvw_d[OriginX]:-0} FV_RECT_AY=${__fvw_d[OriginY]:-0}
    FV_RECT_BX=$(( FV_RECT_AX + ${__fvw_d[SizeX]:-0} )) FV_RECT_BY=$(( FV_RECT_AY + ${__fvw_d[SizeY]:-0} ))
    RESULT="$FV_RECT_AX $FV_RECT_AY $FV_RECT_BX $FV_RECT_BY"
}
# fv.views.getExtent V — RESULT="0 0 SizeX SizeY" and FV_RECT_*
fv.views.getExtent() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" getExtent || return
    local -n __fvw_d=${1}_data
    FV_RECT_AX=0 FV_RECT_AY=0 FV_RECT_BX=${__fvw_d[SizeX]:-0} FV_RECT_BY=${__fvw_d[SizeY]:-0}
    RESULT="0 0 $FV_RECT_BX $FV_RECT_BY"
}

# fv.views.locate V AX AY BX BY — FV Locate: the size clamped by V's
# SizeLimits (virtual), then, when the bounds differ, V's ChangeBounds
# (virtual) and the `move` redraw of old ∪ new
fv.views.locate() {
    if (( $# != 5 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" locate || return
    local -a __fvw_v
    if ! fv.views._ints "$2" "$3" "$4" "$5"; then
        RESULT=''; kk.debug "Error: fv.views.locate: the bounds must be integers"; return 2
    fi
    fv.views._locate "$1" "${__fvw_v[@]}"
}
fv.views._locate() {   # V AX AY BX BY (integers)
    local -n __fvw_d=${1}_data
    local __fvw_ax=$2 __fvw_ay=$3 __fvw_w=$(( $4 - $2 )) __fvw_h=$(( $5 - $3 ))
    local __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4 __fvw_q1 __fvw_q2 __fvw_q3 __fvw_q4
    fv.views._virt "$1" SizeLimits
    if (( __fvw_w < FV_MIN_X )); then __fvw_w=$FV_MIN_X; elif (( __fvw_w > FV_MAX_X )); then __fvw_w=$FV_MAX_X; fi
    if (( __fvw_h < FV_MIN_Y )); then __fvw_h=$FV_MIN_Y; elif (( __fvw_h > FV_MAX_Y )); then __fvw_h=$FV_MAX_Y; fi
    if (( __fvw_ax == ${__fvw_d[OriginX]:-0} && __fvw_ay == ${__fvw_d[OriginY]:-0} )) \
       && (( __fvw_w == ${__fvw_d[SizeX]:-0} && __fvw_h == ${__fvw_d[SizeY]:-0} )); then
        return 0
    fi
    fv.views._abs "$1"
    __fvw_q1=$__fvw_r1 __fvw_q2=$__fvw_r2 __fvw_q3=$__fvw_r3 __fvw_q4=$__fvw_r4
    # ChangeBounds' own redraw is held: the `move` redraw below covers old ∪ new once
    local __fvw_s=0
    __FV_VW_NODRAW=$(( __FV_VW_NODRAW + 1 ))
    fv.views._virt "$1" ChangeBounds "$__fvw_ax" "$__fvw_ay" "$(( __fvw_ax + __fvw_w ))" "$(( __fvw_ay + __fvw_h ))" || __fvw_s=$?
    __FV_VW_NODRAW=$(( __FV_VW_NODRAW - 1 ))
    if (( __fvw_s )); then return "$__fvw_s"; fi
    fv.views._abs "$1"
    if (( __fvw_q1 < __fvw_r1 )); then __fvw_r1=$__fvw_q1; fi
    if (( __fvw_q2 < __fvw_r2 )); then __fvw_r2=$__fvw_q2; fi
    if (( __fvw_q3 > __fvw_r3 )); then __fvw_r3=$__fvw_q3; fi
    if (( __fvw_q4 > __fvw_r4 )); then __fvw_r4=$__fvw_q4; fi
    fv.views._changed move "$1" "${__fvw_d[Owner]-}" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
}
# fv.views.moveTo V X Y — FV MoveTo: locate at (X, Y) with V's size
fv.views.moveTo() {
    if (( $# != 3 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" moveTo || return
    local -a __fvw_v
    if ! fv.views._ints "$2" "$3"; then RESULT=''; kk.debug "Error: fv.views.moveTo: X Y must be integers"; return 2; fi
    local -n __fvw_d=${1}_data
    fv.views._locate "$1" "${__fvw_v[0]}" "${__fvw_v[1]}" \
        "$(( __fvw_v[0] + ${__fvw_d[SizeX]:-0} ))" "$(( __fvw_v[1] + ${__fvw_d[SizeY]:-0} ))"
}
# fv.views.growTo V W H — FV GrowTo: locate at V's origin with size W x H
fv.views.growTo() {
    if (( $# != 3 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" growTo || return
    local -a __fvw_v
    if ! fv.views._ints "$2" "$3"; then RESULT=''; kk.debug "Error: fv.views.growTo: W H must be integers"; return 2; fi
    local -n __fvw_d=${1}_data
    local __fvw_x=${__fvw_d[OriginX]:-0} __fvw_y=${__fvw_d[OriginY]:-0}
    fv.views._locate "$1" "$__fvw_x" "$__fvw_y" "$(( __fvw_x + __fvw_v[0] ))" "$(( __fvw_y + __fvw_v[1] ))"
}
# fv.views.changeBounds V AX AY BX BY — V's ChangeBounds through the
# elision (an override of yours runs; FV calls ChangeBounds directly)
fv.views.changeBounds() {
    if (( $# != 5 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" changeBounds || return
    local -a __fvw_v
    if ! fv.views._ints "$2" "$3" "$4" "$5"; then
        RESULT=''; kk.debug "Error: fv.views.changeBounds: the bounds must be integers"; return 2
    fi
    fv.views._virt "$1" ChangeBounds "${__fvw_v[@]}"
}

# fv.views.makeLocal V X Y / makeGlobal V X Y — a screen point to V's
# coordinates and back: RESULT="X Y" and FV_POINT_X / FV_POINT_Y. From the
# cached absolute origin (FV walks the owner chain; FPC's MakeLocal stops
# that walk at a negative coordinate, this one never does).
fv.views.makeLocal() { fv.views._point "$@" -1 makeLocal; }
fv.views.makeGlobal() { fv.views._point "$@" 1 makeGlobal; }
fv.views._point() {   # V X Y SIGN CALLER
    if (( $# != 5 )); then fv.views._bad "${FUNCNAME[1]#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" "$5" || return
    local -a __fvw_v
    if ! fv.views._ints "$2" "$3"; then RESULT=''; kk.debug "Error: fv.views.$5: X Y must be integers"; return 2; fi
    FV_POINT_X=$(( __fvw_v[0] + $4 * __FV_VW_AX[$1] )) FV_POINT_Y=$(( __fvw_v[1] + $4 * __FV_VW_AY[$1] ))
    RESULT="$FV_POINT_X $FV_POINT_Y"
}
# fv.views.mouseInView V X Y — rc 0 when the screen point (X, Y) lies in V's
# rect (FV MouseInView; not clipped by the owners)
fv.views.mouseInView() {
    if (( $# != 3 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" mouseInView || return
    local -a __fvw_v
    if ! fv.views._ints "$2" "$3"; then fv.views._bad mouseInView 'X Y must be integers'; return; fi
    local -n __fvw_d=${1}_data
    (( __fvw_v[0] >= __FV_VW_AX[$1] && __fvw_v[1] >= __FV_VW_AY[$1] )) \
       && (( __fvw_v[0] < __FV_VW_AX[$1] + ${__fvw_d[SizeX]:-0} && __fvw_v[1] < __FV_VW_AY[$1] + ${__fvw_d[SizeY]:-0} ))
}

# ---- the built-in virtuals' plain bodies (registered in __FV_VW_IMPL) ---------

# TView.ChangeBounds AX AY BX BY — FV: SetBounds; DrawView (the `bounds` redraw)
fv.views._viewChangeBounds() {
    local -n __fvw_d=${1}_data
    local __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4 __fvw_q1 __fvw_q2
    fv.views._abs "$1"
    __fvw_q1=$__fvw_r1 __fvw_q2=$__fvw_r2
    local __fvw_q3=$__fvw_r3 __fvw_q4=$__fvw_r4
    fv.views._setBounds "$1" "$2" "$3" "$4" "$5"
    fv.views._abs "$1"
    if (( __fvw_q1 < __fvw_r1 )); then __fvw_r1=$__fvw_q1; fi
    if (( __fvw_q2 < __fvw_r2 )); then __fvw_r2=$__fvw_q2; fi
    if (( __fvw_q3 > __fvw_r3 )); then __fvw_r3=$__fvw_q3; fi
    if (( __fvw_q4 > __fvw_r4 )); then __fvw_r4=$__fvw_q4; fi
    fv.views._changed bounds "$1" "${__fvw_d[Owner]-}" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
}

# TGroup.ChangeBounds AX AY BX BY — FV: without a size change SetBounds +
# Redraw; with one SetBounds, then each subview (front to back, FV ForEach)
# takes CalcBounds by its GrowMode and its ChangeBounds (both virtual), then
# the group's `bounds` redraw (FV: Lock ... Unlock).
# With a size change only the group's own cache moves first, so that each
# subview's ChangeBounds still sees its old absolute rect (its `bounds` hook
# gets old ∪ new); the whole subtree's cache is recomputed at the end (also
# for a subview whose ChangeBounds override skipped `inherited`).
# FV_RECT_* holds the subview's current bounds before its CalcBounds: an
# override that sets nothing (or fails) keeps the subview where it is. A
# subview that an earlier one destroyed or removed from the group is skipped.
fv.views._groupChangeBounds() {
    local -n __fvw_d=${1}_data __fvw_l=${1}_views
    local __fvw_dx=$(( $4 - $2 - ${__fvw_d[SizeX]:-0} )) __fvw_dy=$(( $5 - $3 - ${__fvw_d[SizeY]:-0} ))
    local __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4 __fvw_q1 __fvw_q2 __fvw_q3 __fvw_q4 __fvw_k __fvw_i
    fv.views._abs "$1"
    __fvw_q1=$__fvw_r1 __fvw_q2=$__fvw_r2 __fvw_q3=$__fvw_r3 __fvw_q4=$__fvw_r4
    if (( __fvw_dx != 0 || __fvw_dy != 0 )); then
        fv.views._setBounds "$1" "$2" "$3" "$4" "$5" 1
        # the subviews' own redraws are held (bulk layout): the group's
        # `bounds` redraw below covers them all, once
        __FV_VW_NODRAW=$(( __FV_VW_NODRAW + 1 ))
        local -a __fvw_kids=("${__fvw_l[@]}")
        for (( __fvw_i = ${#__fvw_kids[@]} - 1; __fvw_i >= 0; __fvw_i-- )); do
            __fvw_k=${__fvw_kids[__fvw_i]}
            fv.views._kid "$1" "$__fvw_k" || continue
            local -n __fvw_kd=${__fvw_k}_data
            FV_RECT_AX=${__fvw_kd[OriginX]:-0} FV_RECT_AY=${__fvw_kd[OriginY]:-0}
            FV_RECT_BX=$(( FV_RECT_AX + ${__fvw_kd[SizeX]:-0} )) FV_RECT_BY=$(( FV_RECT_AY + ${__fvw_kd[SizeY]:-0} ))
            fv.views._virt "$__fvw_k" CalcBounds "$__fvw_dx" "$__fvw_dy" || :
            fv.views._kid "$1" "$__fvw_k" || continue
            fv.views._virt "$__fvw_k" ChangeBounds "$FV_RECT_AX" "$FV_RECT_AY" "$FV_RECT_BX" "$FV_RECT_BY" || :
        done
        __FV_VW_NODRAW=$(( __FV_VW_NODRAW - 1 ))
        fv.views._calc "$1"
    else
        fv.views._setBounds "$1" "$2" "$3" "$4" "$5"
    fi
    fv.views._abs "$1"
    if (( __fvw_q1 < __fvw_r1 )); then __fvw_r1=$__fvw_q1; fi
    if (( __fvw_q2 < __fvw_r2 )); then __fvw_r2=$__fvw_q2; fi
    if (( __fvw_q3 > __fvw_r3 )); then __fvw_r3=$__fvw_q3; fi
    if (( __fvw_q4 > __fvw_r4 )); then __fvw_r4=$__fvw_q4; fi
    fv.views._changed bounds "$1" "${__fvw_d[Owner]-}" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
}

# fv.views._kid G K — rc 0 while K is a live view whose owner is G
fv.views._kid() {
    [[ -n ${__FV_VW_LIVE[$2]-} ]] || return 1
    local -n __fvw_kk=${2}_data
    [ "${__fvw_kk[Owner]-}" = "$1" ]
}

# TView.CalcBounds DX DY — FV CalcBounds: FV_RECT_* = V's bounds after its
# owner grew by (DX, DY), by GrowMode (gfGrowLoX/HiX/LoY/HiY move the edge by
# the delta; gfGrowRel scales it with the owner's new / old size), the width
# capped at MaxViewWidth, the size clamped by SizeLimits (virtual). A view
# without an owner or with GrowMode 0 keeps its bounds.
fv.views._viewCalcBounds() {
    local -n __fvw_d=${1}_data
    local __fvw_m=${__fvw_d[GrowMode]:-0} __fvw_o=${__fvw_d[Owner]-} __fvw_s __fvw_dd
    FV_RECT_AX=${__fvw_d[OriginX]:-0} FV_RECT_AY=${__fvw_d[OriginY]:-0}
    FV_RECT_BX=$(( FV_RECT_AX + ${__fvw_d[SizeX]:-0} )) FV_RECT_BY=$(( FV_RECT_AY + ${__fvw_d[SizeY]:-0} ))
    if (( __fvw_m == 0 )) || [[ -z $__fvw_o ]]; then return 0; fi
    local -n __fvw_od=${__fvw_o}_data
    __fvw_s=${__fvw_od[SizeX]:-0} __fvw_dd=$2
    if (( __fvw_m & FV_GF_GROWLOX )); then fv.views._grow FV_RECT_AX; fi
    if (( __fvw_m & FV_GF_GROWHIX )); then fv.views._grow FV_RECT_BX; fi
    if (( FV_RECT_BX - FV_RECT_AX > __FV_VW_MAXW )); then FV_RECT_BX=$(( FV_RECT_AX + __FV_VW_MAXW )); fi
    __fvw_s=${__fvw_od[SizeY]:-0} __fvw_dd=$3
    if (( __fvw_m & FV_GF_GROWLOY )); then fv.views._grow FV_RECT_AY; fi
    if (( __fvw_m & FV_GF_GROWHIY )); then fv.views._grow FV_RECT_BY; fi
    local __fvw_w=$(( FV_RECT_BX - FV_RECT_AX )) __fvw_h=$(( FV_RECT_BY - FV_RECT_AY ))
    local __fvw_ax=$FV_RECT_AX __fvw_ay=$FV_RECT_AY
    fv.views._virt "$1" SizeLimits
    if (( __fvw_w < FV_MIN_X )); then __fvw_w=$FV_MIN_X; elif (( __fvw_w > FV_MAX_X )); then __fvw_w=$FV_MAX_X; fi
    if (( __fvw_h < FV_MIN_Y )); then __fvw_h=$FV_MIN_Y; elif (( __fvw_h > FV_MAX_Y )); then __fvw_h=$FV_MAX_Y; fi
    # (a SizeLimits override of yours may use FV_RECT_*: put them back)
    FV_RECT_AX=$__fvw_ax FV_RECT_AY=$__fvw_ay FV_RECT_BX=$(( __fvw_ax + __fvw_w )) FV_RECT_BY=$(( __fvw_ay + __fvw_h ))
}
# FV GrowI: the edge (a variable name) by the caller's __fvw_dd / __fvw_s /
# __fvw_m: + delta, or relative I := (I*S + (S-D) shr 1) div (S-D), 1 when
# the old size S-D is 0
fv.views._grow() {
    local -n __fvw_e=$1
    if (( ! (__fvw_m & FV_GF_GROWREL) )); then __fvw_e=$(( __fvw_e + __fvw_dd ))
    elif (( __fvw_s == __fvw_dd )); then __fvw_e=1
    else __fvw_e=$(( (__fvw_e * __fvw_s + ((__fvw_s - __fvw_dd) >> 1)) / (__fvw_s - __fvw_dd) )); fi
}

# TView.SizeLimits — FV: FV_MIN_X/_Y = 0; FV_MAX_X/_Y = the owner's size
# (FV TGroup.ClipChilds is true), high(Sw_Integer) without an owner
fv.views._viewSizeLimits() {
    local -n __fvw_d=${1}_data
    local __fvw_o=${__fvw_d[Owner]-}
    FV_MIN_X=0 FV_MIN_Y=0
    if [[ -n $__fvw_o ]]; then
        local -n __fvw_od=${__fvw_o}_data
        FV_MAX_X=${__fvw_od[SizeX]:-0} FV_MAX_Y=${__fvw_od[SizeY]:-0}
    else
        FV_MAX_X=$__FV_VW_HIGH FV_MAX_Y=$__FV_VW_HIGH
    fi
}

# TView.GetHelpCtx (func) — FV: hcDragging while sfDragging, else HelpCtx
fv.views._viewGetHelpCtx() {
    local -n __fvw_d=${1}_data
    if (( ${__fvw_d[State]:-0} & FV_SF_DRAGGING )); then RESULT=$FV_HC_DRAGGING
    else RESULT=${__fvw_d[HelpCtx]:-0}; fi
}
# TGroup.GetHelpCtx (func) — FV: Current's GetHelpCtx (virtual), else TView's
fv.views._groupGetHelpCtx() {
    local -n __fvw_d=${1}_data
    local __fvw_c=${__fvw_d[Current]-}
    RESULT=$FV_HC_NOCONTEXT
    if [[ -n $__fvw_c && -n ${__FV_VW_LIVE[$__fvw_c]-} ]]; then fv.views._virt "$__fvw_c" GetHelpCtx; fi
    if [[ ${RESULT-} == "$FV_HC_NOCONTEXT" ]]; then fv.views._viewGetHelpCtx "$1"; fi
}

# ==== drawing (P2 stage 2c-2; design §1.5, §1.7, §1.9, §1.10) ===================
#
# The painter: back to front, no z-order clip walk. paint(V, R) draws V (its
# Draw through the elision) clipped to V's clip ∩ R; a group's Draw paints its
# visible subviews back to front, skipping one that a COVERING front sibling
# hides entirely (a leaf, or a group whose back-most subview is a visible
# frame of its full size: "Draw must cover its rect"), and shades the
# shadow of each sfShadow subview after drawing it. drawView V = paint(V) +
# V's shadow + over(V, S(V)): every visible view in front of V or of one of
# its owners whose S() meets the rectangle is painted again, clipped to it.
# drawUnder(G, rect) = paint(G, rect) + over(G, rect). The terminal update
# (fv.video.updateScreen) runs once at the end of each outermost drawing
# entry, unless lockScreenUpdate or a user lock holds it.
#
# The fv.video clip: the outermost drawing entry saves the caller's clip
# (fv.video.getClip) and puts it back at its end. Each paint sets the clip
# to what it may write; a paint that returns into a Draw body (a nested
# drawView, a decoration after `inherited Draw`) puts that Draw's clip back,
# one that returns into a framework loop does not (the next paint sets its
# own). The drawing context (FV_DRAW_*, FV_CLIP_*) is saved and restored by
# each paint, so a drawView or drawPart nested inside a Draw leaves the outer
# Draw's context intact.
#
# Rules on top (review round of 2c-2): a view whose Draw runs is never painted
# again from inside it (__FV_VW_INDRAW; a nested draw behind a covering one of
# them leaves that part out: fv.views._nestCut); a change inside a frameless
# group is repainted from the first covering owner (fv.views._drawUnder);
# screen rows with wide cells are repainted across the whole width
# (fv.views._bands); a Draw's rc is ignored (FV procedure).

# fv.views._begin / fv.views._end — a drawing entry's frame: the caller
# declares `local __fvw_bg __fvw_b1 __fvw_b2 __fvw_b3 __fvw_b4`
fv.views._begin() {
    __fvw_bg=$__FV_VW_INGRP __fvw_b1=$__FV_VW_P1 __fvw_b2=$__FV_VW_P2 __fvw_b3=$__FV_VW_P3 __fvw_b4=$__FV_VW_P4
    if (( __FV_VW_DEPTH == 0 )); then
        # (the caller's clip read as a friend: fv.video's __FV_VS_CX1 .. CY2,
        # meaningful only while a screen exists)
        if (( ${__FV_VS_H:-0} )); then
            __FV_VW_UCLIP=1 __FV_VW_U1=$__FV_VS_CX1 __FV_VW_U2=$__FV_VS_CY1 __FV_VW_U3=$__FV_VS_CX2 __FV_VW_U4=$__FV_VS_CY2
        else
            __FV_VW_UCLIP=''
        fi
    fi
    __FV_VW_DEPTH=$(( __FV_VW_DEPTH + 1 )) __FV_VW_INGRP=1
}
fv.views._end() {
    __FV_VW_DEPTH=$(( __FV_VW_DEPTH - 1 ))
    __FV_VW_INGRP=$__fvw_bg __FV_VW_P1=$__fvw_b1 __FV_VW_P2=$__fvw_b2 __FV_VW_P3=$__fvw_b3 __FV_VW_P4=$__fvw_b4
    if (( __FV_VW_DEPTH == 0 )); then
        if [[ -n $__FV_VW_UCLIP ]]; then fv.video._clipf "$__FV_VW_U1" "$__FV_VW_U2" "$__FV_VW_U3" "$__FV_VW_U4"; fi
    elif (( ! __fvw_bg )); then
        fv.video._clipf "$__fvw_b1" "$__fvw_b2" "$__fvw_b3" "$__fvw_b4"
    fi
    return 0
}

# fv.views._flush — the terminal update, unless held (lockScreenUpdate, a
# user lock) or inside another drawing entry (the outermost one flushes)
fv.views._flush() {
    if (( __FV_VW_LSU == 0 && __FV_VW_LOCKN == 0 && __FV_VW_DEPTH == 0 )); then
        __FV_VW_PEND=0
        # (a redraw's forced update waits here while the update is held)
        if (( __FV_VW_FORCE )); then __FV_VW_FORCE=0; fv.video.updateScreen force || :
        else fv.video.updateScreen || :; fi
    elif (( __FV_VW_DEPTH == 0 )); then
        __FV_VW_PEND=1
    fi
    return 0
}

# fv.views._release — the end of a framework sequence that held the update
# itself (__FV_VW_LSU += 1 at its start; D17: no Lock): the count back, and
# the terminal updated when something was held back meanwhile and nothing
# holds it any more. RESULT is kept
fv.views._release() {
    __FV_VW_LSU=$(( __FV_VW_LSU - 1 ))
    if (( __FV_VW_LSU < 0 )); then __FV_VW_LSU=0; fi
    if (( __FV_VW_LSU == 0 )) && [[ -n $__FV_VW_CPEND ]]; then fv.views._cursorNow; fi
    if (( __FV_VW_PEND && __FV_VW_LSU == 0 && __FV_VW_LOCKN == 0 )); then
        local __fvw_rr=${RESULT-}
        fv.views._flush
        RESULT=$__fvw_rr
    fi
    return 0
}

# fv.views._cursorLater V — resetCursor for V's tree, now, or (while the
# update is held: lockScreenUpdate, a framework sequence) once at the release
# (fv.views._release, unlockScreenUpdate): a focus change sets and clears
# sfFocused on several views. _cursorNow runs the one that waits
fv.views._cursorLater() {
    if (( __FV_VW_LSU > 0 )); then __FV_VW_CPEND=$1; else fv.views._resetCursor "$1"; fi
}
# fv.views._showNow — the terminal update that only the modal loops' own
# per-event holds (__FV_VW_EH) keep back: sent now (with the cursor waiting
# for resetCursor), so a nested modal view or a mouse tracking loop inside a
# handler shows its frames. A hold of the caller's (lockScreenUpdate, a user
# lock, a drawing entry) keeps it back still. RESULT is kept
fv.views._showNow() {
    if (( __FV_VW_LSU != __FV_VW_EH || __FV_VW_LOCKN || __FV_VW_DEPTH )); then return 0; fi
    if (( ! __FV_VW_PEND )) && [[ -z $__FV_VW_CPEND ]]; then return 0; fi
    local __fvw_hs=$__FV_VW_LSU __fvw_rr=${RESULT-}
    __FV_VW_LSU=0
    if [[ -n $__FV_VW_CPEND ]]; then fv.views._cursorNow; fi
    if (( __FV_VW_PEND )); then fv.views._flush; fi
    __FV_VW_LSU=$__fvw_hs
    RESULT=$__fvw_rr
}
fv.views._cursorNow() {
    local __fvw_cv=$__FV_VW_CPEND
    __FV_VW_CPEND=''
    if [[ -n $__fvw_cv && -n ${__FV_VW_LIVE[$__fvw_cv]-} ]]; then fv.views._resetCursor "$__fvw_cv"; fi
}

# fv.views._drawable V — rc 0 when V may be drawn now: drawing not held
# (NODRAW), V and every owner visible, none of them locked (fv.views.lock:
# its unlock redraws it), and the root of V's tree has sfExposed (FV: a view
# is drawn only inside the application's tree; fv.app sets the bit on the
# application, a desktop-less user or test on its root group)
fv.views._drawable() {
    if (( __FV_VW_NODRAW > 0 )); then return 1; fi
    # (D21: no lock, no SKIP and the chain known: one arithmetic test over
    # the live State fields of V and its owners)
    if [[ -n ${__FV_VW_DEX[$1]-} && -z $__FV_VW_SKIP && -z ${__FV_VW_LK[*]-} ]]; then (( ${__FV_VW_DEX[$1]} )); return; fi
    fv.views._drawableX "$1"
}
# fv.views._drawableX V — _drawable's walk: the answer, and V's chain test
# stored in __FV_VW_DEX
fv.views._drawableX() {
    local __fvw_v=$1 __fvw_e='' __fvw_ok=1
    while :; do
        local -n __fvw_dd=${__fvw_v}_data
        __fvw_e+="${__fvw_v}_data[State] & "
        if (( __fvw_ok )); then
            if (( ! (${__fvw_dd[State]:-0} & FV_SF_VISIBLE) )) || [[ -n ${__FV_VW_LK[$__fvw_v]-} ]]; then __fvw_ok=0
            # (a view the running framework sequence draws whole right after)
            elif [[ -n $__FV_VW_SKIP ]] && [ "$__fvw_v" = "$__FV_VW_SKIP" ]; then __fvw_ok=0; fi
        fi
        if [[ -z ${__fvw_dd[Owner]-} ]]; then break; fi
        __fvw_v=${__fvw_dd[Owner]}
    done
    __FV_VW_DEX[$1]="($__fvw_e$FV_SF_VISIBLE) && (${__fvw_v}_data[State] & $FV_SF_EXPOSED)"
    (( __fvw_ok && (${__fvw_dd[State]:-0} & FV_SF_EXPOSED) ))
}

# fv.views._srect V — __fvw_r1..4 (the caller's): S(V), V's absolute rect
# widened by FV's ShadowSize (2, 1) when V has sfShadow
fv.views._srect() {
    local -n __fvw_sd=${1}_data
    __fvw_r1=${__FV_VW_AX[$1]} __fvw_r2=${__FV_VW_AY[$1]}
    __fvw_r3=$(( __fvw_r1 + ${__fvw_sd[SizeX]:-0} )) __fvw_r4=$(( __fvw_r2 + ${__fvw_sd[SizeY]:-0} ))
    if (( ${__fvw_sd[State]:-0} & FV_SF_SHADOW )); then __fvw_r3=$(( __fvw_r3 + 2 )) __fvw_r4=$(( __fvw_r4 + 1 )); fi
}

# fv.views._paint V R1 R2 R3 R4 — paint V clipped to its clip ∩ the absolute
# rectangle R (no flush, no over): the context set, V's Draw through the
# elision (inline: a built-in TGroup.Draw runs as fv.views._groupDraw V 1),
# the context restored
fv.views._paint() {
    # re-entrancy: a view whose Draw is running (on the paint stack: the view
    # and the groups painting it) is never painted again from inside it
    if [[ -n ${__FV_VW_INDRAW[$1]-} ]]; then return 0; fi
    local __fvw_1=${__FV_VW_C1[$1]} __fvw_2=${__FV_VW_C2[$1]} __fvw_3=${__FV_VW_C3[$1]} __fvw_4=${__FV_VW_C4[$1]}
    if (( $2 > __fvw_1 )); then __fvw_1=$2; fi
    if (( $3 > __fvw_2 )); then __fvw_2=$3; fi
    if (( $4 < __fvw_3 )); then __fvw_3=$4; fi
    if (( $5 < __fvw_4 )); then __fvw_4=$5; fi
    if (( __fvw_1 >= __fvw_3 || __fvw_2 >= __fvw_4 )); then return 0; fi
    local __fvw_sv=$FV_DRAW_VIEW __fvw_sx=$FV_DRAW_X __fvw_sy=$FV_DRAW_Y __fvw_sp=$FV_DRAW_PAL
    local __fvw_c1=$FV_CLIP_X1 __fvw_c2=$FV_CLIP_Y1 __fvw_c3=$FV_CLIP_X2 __fvw_c4=$FV_CLIP_Y2
    local __fvw_p1=$__FV_VW_P1 __fvw_p2=$__FV_VW_P2 __fvw_p3=$__FV_VW_P3 __fvw_p4=$__FV_VW_P4
    local __fvw_g=$__FV_VW_INGRP __fvw_f __fvw_o
    if [[ -z ${__FV_VW_PAL[$1]+x} ]]; then fv.views._pal "$1"; fi
    FV_DRAW_VIEW=$1 FV_DRAW_X=${__FV_VW_AX[$1]} FV_DRAW_Y=${__FV_VW_AY[$1]} FV_DRAW_PAL=${__FV_VW_PAL[$1]}
    FV_CLIP_X1=$(( __fvw_1 - FV_DRAW_X )) FV_CLIP_Y1=$(( __fvw_2 - FV_DRAW_Y ))
    FV_CLIP_X2=$(( __fvw_3 - FV_DRAW_X )) FV_CLIP_Y2=$(( __fvw_4 - FV_DRAW_Y ))
    __FV_VW_P1=$__fvw_1 __FV_VW_P2=$__fvw_2 __FV_VW_P3=$__fvw_3 __FV_VW_P4=$__fvw_4 __FV_VW_INGRP=0
    fv.video._clipf "$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4"
    __fvw_o=${1}_class
    __fvw_o="${!__fvw_o-}_class_method_owner[Draw]"
    __fvw_f=${__FV_VW_IMPL[${!__fvw_o-}.Draw]-}
    # Draw is an FV procedure: its rc is ignored (a Draw of yours ending in a
    # false test must not end a caller running under set -e)
    __FV_VW_INDRAW[$1]=1
    if [[ -z $__fvw_f ]]; then "$1.Draw" || :
    elif [ "$__fvw_f" = fv.views._groupDraw ]; then fv.views._groupDraw "$1" 1 || :
    else "$__fvw_f" "$1" || :; fi
    unset '__FV_VW_INDRAW[$1]'
    FV_DRAW_VIEW=$__fvw_sv FV_DRAW_X=$__fvw_sx FV_DRAW_Y=$__fvw_sy FV_DRAW_PAL=$__fvw_sp
    FV_CLIP_X1=$__fvw_c1 FV_CLIP_Y1=$__fvw_c2 FV_CLIP_X2=$__fvw_c3 FV_CLIP_Y2=$__fvw_c4
    __FV_VW_P1=$__fvw_p1 __FV_VW_P2=$__fvw_p2 __FV_VW_P3=$__fvw_p3 __FV_VW_P4=$__fvw_p4 __FV_VW_INGRP=$__fvw_g
    if (( ! __fvw_g )); then fv.video._clipf "$__fvw_p1" "$__fvw_p2" "$__fvw_p3" "$__fvw_p4"; fi
    return 0
}

# fv.views._shade V R1 R2 R3 R4 — V's shadow (FV ShadowSize 2 x 1: the two
# columns right of V from its second row, the row below V from its third
# column) ∩ R ∩ V's owner's clip, attribute only (fv.video._shadef, the
# shadow symbol V). rc 0 when something was shaded (the fv.video clip was set
# to R ∩ the owner's clip), 1 when nothing
fv.views._shade() {
    local -n __fvw_hd=${1}_data
    local __fvw_o=${__fvw_hd[Owner]-}
    if [[ -z $__fvw_o ]] || (( ! (${__fvw_hd[State]:-0} & FV_SF_SHADOW) )); then return 1; fi
    local __fvw_1=${__FV_VW_C1[$__fvw_o]} __fvw_2=${__FV_VW_C2[$__fvw_o]} __fvw_3=${__FV_VW_C3[$__fvw_o]} __fvw_4=${__FV_VW_C4[$__fvw_o]}
    if (( $2 > __fvw_1 )); then __fvw_1=$2; fi
    if (( $3 > __fvw_2 )); then __fvw_2=$3; fi
    if (( $4 < __fvw_3 )); then __fvw_3=$4; fi
    if (( $5 < __fvw_4 )); then __fvw_4=$5; fi
    if (( __fvw_1 >= __fvw_3 || __fvw_2 >= __fvw_4 )); then return 1; fi
    local __fvw_x=${__FV_VW_AX[$1]} __fvw_y=${__FV_VW_AY[$1]} __fvw_w=${__fvw_hd[SizeX]:-0} __fvw_h=${__fvw_hd[SizeY]:-0}
    local __fvw_ax __fvw_ay __fvw_bx __fvw_by __fvw_n=0
    local -a __fvw_q=(
        "$(( __fvw_x + __fvw_w ))" "$(( __fvw_y + 1 ))" "$(( __fvw_x + __fvw_w + 2 ))" "$(( __fvw_y + __fvw_h + 1 ))"
        "$(( __fvw_x + 2 ))" "$(( __fvw_y + __fvw_h ))" "$(( __fvw_x + __fvw_w ))" "$(( __fvw_y + __fvw_h + 1 ))"
    )
    for __fvw_x in 0 4; do
        __fvw_ax=${__fvw_q[__fvw_x]} __fvw_ay=${__fvw_q[__fvw_x+1]} __fvw_bx=${__fvw_q[__fvw_x+2]} __fvw_by=${__fvw_q[__fvw_x+3]}
        if (( __fvw_ax < __fvw_1 )); then __fvw_ax=$__fvw_1; fi
        if (( __fvw_ay < __fvw_2 )); then __fvw_ay=$__fvw_2; fi
        if (( __fvw_bx > __fvw_3 )); then __fvw_bx=$__fvw_3; fi
        if (( __fvw_by > __fvw_4 )); then __fvw_by=$__fvw_4; fi
        if (( __fvw_ax >= __fvw_bx || __fvw_ay >= __fvw_by )); then continue; fi
        if (( ! __fvw_n )); then fv.video._clipf "$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4"; __fvw_n=1; fi
        fv.video._shadef "$__fvw_ax" "$__fvw_ay" "$(( __fvw_bx - __fvw_ax ))" "$(( __fvw_by - __fvw_ay ))" || :
    done
    (( __fvw_n ))
}

# fv.views._covers V — rc 0 when V paints its whole rect: a leaf, or a group
# whose back-most subview is a visible TFrame of the group's full size (a
# frameless group is not covering; a shadow never covers)
fv.views._covers() {
    if [[ -z ${__FV_VW_GRP[$1]-} ]]; then return 0; fi
    local -n __fvw_vl=${1}_views
    if (( ! ${#__fvw_vl[@]} )); then return 1; fi
    local __fvw_f=${__fvw_vl[0]}
    if [[ -z ${__FV_VW_FRM[$__fvw_f]-} ]]; then return 1; fi
    local -n __fvw_fd=${__fvw_f}_data __fvw_gd=${1}_data
    if (( ! (${__fvw_fd[State]:-0} & FV_SF_VISIBLE) )); then return 1; fi
    if (( ${__fvw_fd[OriginX]:-0} != 0 || ${__fvw_fd[OriginY]:-0} != 0 )); then return 1; fi
    (( ${__fvw_fd[SizeX]:-0} == ${__fvw_gd[SizeX]:-0} && ${__fvw_fd[SizeY]:-0} == ${__fvw_gd[SizeY]:-0} ))
}

# fv.views._over V — paint, clipped to each rectangle of the caller's array
# __fvw_rs (absolute X1 Y1 X2 Y2, ...), every visible view in front of V or
# of one of V's owners whose S() meets it (back to front at each level, the
# innermost level first), and its shadow. `ring` (fv.views._frameBorder): the
# rectangles are the one-cell pieces of a frame's border, which lets a view
# inside them pass at once. D21: the views in front come from the structure
# cache __FV_VW_FRL (fv.views._frontList); most views have none in front
fv.views._over() {
    if (( ! ${#__fvw_rs[@]} )); then return 0; fi
    if [[ -z ${__FV_VW_FRL[$1]+x} ]]; then fv.views._frontList "$1"; fi
    if [[ -n ${__FV_VW_FRL[$1]} ]]; then fv.views._overList "$1" "${2-}"; fi
    return 0
}
# fv.views._frontList V — __FV_VW_FRL[V] = the views in front of V or of an
# owner (each followed by a blank): at each owner level from V's up, the
# siblings in front of the path node, back to front
fv.views._frontList() {
    local __fvw_v=$1 __fvw_o __fvw_i __fvw_f=''
    while :; do
        local -n __fvw_vd=${__fvw_v}_data
        __fvw_o=${__fvw_vd[Owner]-}
        if [[ -z $__fvw_o ]]; then break; fi
        local -n __fvw_ol=${__fvw_o}_views
        fv.views._idx "$__fvw_o" "$__fvw_v"
        for (( __fvw_i = __fvw_i + 1; __fvw_i < ${#__fvw_ol[@]}; __fvw_i++ )); do __fvw_f+="${__fvw_ol[__fvw_i]} "; done
        __fvw_v=$__fvw_o
    done
    __FV_VW_FRL[$1]=$__fvw_f
}
# fv.views._overList V [ring] — _over's walk over V's front list: every
# visible view whose S() meets a rectangle is painted over it, with its
# shadow. Apart because bash copies a function's body on every call
fv.views._overList() {
    local __fvw_q=${__FV_VW_FRL[$1]} __fvw_k __fvw_j __fvw_m=${#__fvw_rs[@]} __fvw_t __fvw_rg=0 __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
    local __fvw_u1=${__fvw_rs[0]} __fvw_u2=${__fvw_rs[1]} __fvw_u3=${__fvw_rs[2]} __fvw_u4=${__fvw_rs[3]}
    if [ "${2-}" = ring ]; then __fvw_rg=1; fi
    # (the rectangles' bounding box: a view in front that misses it is passed with one test)
    for (( __fvw_j = 4; __fvw_j < __fvw_m; __fvw_j += 4 )); do
        if (( __fvw_rs[__fvw_j] < __fvw_u1 )); then __fvw_u1=${__fvw_rs[__fvw_j]}; fi
        if (( __fvw_rs[__fvw_j+1] < __fvw_u2 )); then __fvw_u2=${__fvw_rs[__fvw_j+1]}; fi
        if (( __fvw_rs[__fvw_j+2] > __fvw_u3 )); then __fvw_u3=${__fvw_rs[__fvw_j+2]}; fi
        if (( __fvw_rs[__fvw_j+3] > __fvw_u4 )); then __fvw_u4=${__fvw_rs[__fvw_j+3]}; fi
    done
    while [[ -n $__fvw_q ]]; do
        __fvw_k=${__fvw_q%% *} __fvw_q=${__fvw_q#*[ ]}
        local -n __fvw_kd=${__fvw_k}_data
        __fvw_t=${__fvw_kd[State]:-0}
        # (hidden, or a view whose Draw is running: not painted again from inside it)
        if (( ! (__fvw_t & FV_SF_VISIBLE) )) || [[ -n ${__FV_VW_INDRAW[$__fvw_k]-} ]]; then continue; fi
        # S(k), as fv.views._srect
        __fvw_r1=${__FV_VW_AX[$__fvw_k]} __fvw_r2=${__FV_VW_AY[$__fvw_k]}
        __fvw_r3=$(( __fvw_r1 + ${__fvw_kd[SizeX]:-0} + (__fvw_t & FV_SF_SHADOW ? 2 : 0) )) __fvw_r4=$(( __fvw_r2 + ${__fvw_kd[SizeY]:-0} + (__fvw_t & FV_SF_SHADOW ? 1 : 0) ))
        if (( __fvw_r1 >= __fvw_u3 || __fvw_u1 >= __fvw_r3 || __fvw_r2 >= __fvw_u4 || __fvw_u2 >= __fvw_r4 )); then continue; fi
        # (ring: the rectangles are one-cell pieces of a frame's border,
        # each on an edge of their box: a view strictly inside the box
        # meets none of them)
        if (( __fvw_rg && __fvw_r1 > __fvw_u1 && __fvw_r3 < __fvw_u3 && __fvw_r2 > __fvw_u2 && __fvw_r4 < __fvw_u4 )); then continue; fi
        for (( __fvw_j = 0; __fvw_j < __fvw_m; __fvw_j += 4 )); do
            if (( __fvw_r1 >= __fvw_rs[__fvw_j+2] || __fvw_rs[__fvw_j] >= __fvw_r3 )); then continue; fi
            if (( __fvw_r2 < __fvw_rs[__fvw_j+3] && __fvw_rs[__fvw_j+1] < __fvw_r4 )); then
                fv.views._paint "$__fvw_k" "${__fvw_rs[@]:__fvw_j:4}"
                if (( ${__fvw_kd[State]:-0} & FV_SF_SHADOW )); then fv.views._shade "$__fvw_k" "${__fvw_rs[@]:__fvw_j:4}" || :; fi
            fi
        done
    done
}

# fv.views._nestCut X — for a drawView / drawPart nested inside a Draw: take
# out of the caller's rectangles __fvw_rs the clip of the COVERING view in
# front of X whose Draw is running (the paint stack): X is behind it, so
# what X paints must not land on it (that view finishes its own Draw). One
# such view at most (the paint stack is one chain); found by walking X's
# owners for a front sibling on the stack, then down the stack to the first
# covering view. Up to four pieces per rectangle
fv.views._nestCut() {
    if (( ! ${#__FV_VW_INDRAW[@]} )); then return 0; fi
    local __fvw_v=$1 __fvw_o __fvw_i=-1 __fvw_n __fvw_k='' __fvw_c __fvw_j
    while [[ -z $__fvw_k ]]; do
        local -n __fvw_vd=${__fvw_v}_data
        __fvw_o=${__fvw_vd[Owner]-}
        if [[ -z $__fvw_o ]]; then return 0; fi
        local -n __fvw_ol=${__fvw_o}_views
        __fvw_n=${#__fvw_ol[@]}
        fv.views._idx "$__fvw_o" "$__fvw_v"
        for (( __fvw_i = __fvw_i + 1; __fvw_i < __fvw_n; __fvw_i++ )); do
            if [[ -n ${__FV_VW_INDRAW[${__fvw_ol[__fvw_i]}]-} ]]; then __fvw_k=${__fvw_ol[__fvw_i]}; break; fi
        done
        __fvw_v=$__fvw_o
    done
    # down the stack to the first view that covers its rect
    while ! fv.views._covers "$__fvw_k"; do
        local -n __fvw_kl=${__fvw_k}_views
        __fvw_c=''
        for __fvw_j in "${__fvw_kl[@]}"; do
            if [[ -n ${__FV_VW_INDRAW[$__fvw_j]-} ]]; then __fvw_c=$__fvw_j; break; fi
        done
        if [[ -z $__fvw_c ]]; then return 0; fi
        __fvw_k=$__fvw_c
    done
    local __fvw_e1=${__FV_VW_C1[$__fvw_k]} __fvw_e2=${__FV_VW_C2[$__fvw_k]} __fvw_e3=${__FV_VW_C3[$__fvw_k]} __fvw_e4=${__FV_VW_C4[$__fvw_k]}
    local __fvw_1 __fvw_2 __fvw_3 __fvw_4 __fvw_t __fvw_b
    local -a __fvw_nr=()
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        __fvw_1=${__fvw_rs[__fvw_j]} __fvw_2=${__fvw_rs[__fvw_j+1]} __fvw_3=${__fvw_rs[__fvw_j+2]} __fvw_4=${__fvw_rs[__fvw_j+3]}
        if (( __fvw_1 >= __fvw_e3 || __fvw_e1 >= __fvw_3 || __fvw_2 >= __fvw_e4 || __fvw_e2 >= __fvw_4 )); then
            __fvw_nr+=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4"); continue
        fi
        __fvw_t=$__fvw_2 __fvw_b=$__fvw_4
        if (( __fvw_2 < __fvw_e2 )); then __fvw_nr+=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_e2"); __fvw_t=$__fvw_e2; fi
        if (( __fvw_e4 < __fvw_4 )); then __fvw_nr+=("$__fvw_1" "$__fvw_e4" "$__fvw_3" "$__fvw_4"); __fvw_b=$__fvw_e4; fi
        if (( __fvw_1 < __fvw_e1 )); then __fvw_nr+=("$__fvw_1" "$__fvw_t" "$__fvw_e1" "$__fvw_b"); fi
        if (( __fvw_e3 < __fvw_3 )); then __fvw_nr+=("$__fvw_e3" "$__fvw_t" "$__fvw_3" "$__fvw_b"); fi
    done
    __fvw_rs=("${__fvw_nr[@]}")
}

# fv.views._bands [WIDEN] — wide characters and the repaint edges: a write cut
# by a clip edge leaves a blank in the visible half of a wide character and
# blanks the other half of the one it covers (fv.video's rules), so a repaint
# rectangle whose edge cuts a wide character would differ from a full
# repaint. Rows that hold or held wide cells (__FV_VW_WROW, kept by
# fv.views._wideMark) are therefore looked at. Stage 3a-2, the edge test: such
# a row is repainted across the whole screen width (a full-width band) only
#   * when a wide pair straddles the left or the right edge X1 / X2 of a
#     rectangle on it: fv.video's row (read as a friend) holds a continuation
#     cell at X1 or at X2. Outside the rectangle the screen already is what a
#     full repaint gives, so such a pair is in the new picture too, and only
#     there can a clipped paint differ from a full repaint (a pair cut at a
#     clip edge of the view itself is cut the same way by both);
#   * when two rectangles on the row meet or overlap (the edge between them
#     lies inside what is repainted: the screen there tells nothing).
# Otherwise the rectangle alone leaves the full repaint's cells. WIDEN 1 (the
# repaints after a view left cells it covered: drawUnder, overOnly): a view
# that no longer covers an edge cell uncovers the whole pair it had blanked
# half of, so the picture can change one cell beyond the rectangle, where
# that blanked half shows a space — a rectangle is widened by one cell on
# each side where one of its wide rows has a space beside the edge (inside
# the screen), and the test runs on the widened edges too (the extra cells
# of its other rows are only repainted as they are: no split). A caller whose
# locale is not UTF-8 (the friend read indexes characters) and a paint
# nested in a Draw (fv.views._nestCut's pieces border a view whose paint is
# running) band every such row, as before stage 3a-2. The callers run it
# BEFORE they write anything (the test reads the screen as it was). A
# rectangle with a row to band is split into runs at the band edges, a run to
# band becoming one full-width band (each row banded once).
# __FV_VW_BANDED = the number of bands and widened rectangles made (0:
# __fvw_rs is unchanged)
fv.views._bands() {
    __FV_VW_BANDED=0
    if (( ! ${#__FV_VW_WROW[@]} )); then return 0; fi
    # (the common case without the long body: one rectangle, no WIDEN, not
    # nested in a Draw (that one bands every marked row), and no
    # row of it holds a continuation cell now (fv.video's WIDE bit 1) — then
    # no wide pair lies at its edges, in any caller locale. Rows stay marked
    # once wide cells were seen (WNEW), so this keeps a list that showed CJK
    # and now shows other text as cheap as before; a caller IFS that joins
    # with 1 or 3 only takes the long body)
    if (( ${#__fvw_rs[@]} == 4 && ! ${1:-0} && ! ${#__FV_VW_INDRAW[@]} )); then
        local __fvw_y=${__fvw_rs[1]} __fvw_e=${__fvw_rs[3]}
        if (( __fvw_y < 0 )); then __fvw_y=0; fi
        if (( __fvw_e > FV_SCREEN_H )); then __fvw_e=$FV_SCREEN_H; fi
        if (( __fvw_e <= __fvw_y )) || [[ "${__FV_VS_WIDE[*]:__fvw_y:__fvw_e-__fvw_y}" != *[13]* ]]; then return 0; fi
    fi
    fv.views._bandsx "$@"
}
# fv.views._bandsx [WIDEN] — fv.views._bands' long body
fv.views._bandsx() {
    local __fvw_j __fvw_y __fvw_r __fvw_s __fvw_w=$FV_SCREEN_W __fvw_q __fvw_e __fvw_k __fvw_x1 __fvw_x2 __fvw_a __fvw_b __fvw_bw=${1:-0}
    local -a __fvw_nr=() __fvw_dn=() __fvw_hb=() __fvw_iv=() __fvw_wl=() __fvw_wr=()
    if (( ${#__FV_VS_PB} == 2 && ! ${#__FV_VW_INDRAW[@]} )); then
        # (pass 1, the edge test: __fvw_hb[y] = 1 for a row to band;
        # __fvw_wl / __fvw_wr [j/4] = 1 when rectangle j widens to the left /
        # right (WIDEN: a space beside its edge on one of its wide rows, the
        # half a view it no longer covers may have blanked); __fvw_iv[y] = 1
        # once a rectangle covers the row)
        for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
            __fvw_x1=${__fvw_rs[__fvw_j]} __fvw_x2=${__fvw_rs[__fvw_j+2]}
            __fvw_y=${__fvw_rs[__fvw_j+1]} __fvw_e=${__fvw_rs[__fvw_j+3]}
            if (( __fvw_y < 0 )); then __fvw_y=0; fi
            if (( __fvw_e > FV_SCREEN_H )); then __fvw_e=$FV_SCREEN_H; fi
            for (( ; __fvw_y < __fvw_e; __fvw_y++ )); do
                if [[ -z ${__FV_VW_WROW[__fvw_y]-} || -n ${__fvw_hb[__fvw_y]-} ]]; then continue; fi
                # (a row that holds no continuation cell now, fv.video's
                # WIDE bit 1, has no pair at an edge: no character read; such
                # rows stay marked once seen, so this keeps them cheap)
                if (( ${__FV_VS_WIDE[__fvw_y]:-0} & 1 )); then
                    __fvw_s=${__FV_VS_CH[__fvw_y]-}
                    if (( __fvw_x1 > 0 )) && [[ ${__fvw_s:__fvw_x1:1} == "$__FV_VS_CONT" ]] || [[ ${__fvw_s:__fvw_x2:1} == "$__FV_VS_CONT" ]]; then
                        __fvw_hb[__fvw_y]=1
                        continue
                    fi
                elif (( __fvw_bw )); then
                    __fvw_s=${__FV_VS_CH[__fvw_y]-}
                fi
                if (( __fvw_bw )); then
                    if (( __fvw_x1 > 0 )) && [[ ${__fvw_s:__fvw_x1-1:1} == ' ' ]]; then __fvw_wl[__fvw_j/4]=1; fi
                    if [[ ${__fvw_s:__fvw_x2:1} == ' ' ]]; then __fvw_wr[__fvw_j/4]=1; fi
                fi
                if [[ -n ${__fvw_iv[__fvw_y]-} ]]; then
                    # (an earlier rectangle on this row that meets this one;
                    # WIDEN: as both may be widened)
                    for (( __fvw_k = 0; __fvw_k < __fvw_j; __fvw_k += 4 )); do
                        __fvw_a=$(( __fvw_rs[__fvw_k] - 2 * __fvw_bw )) __fvw_b=$(( __fvw_rs[__fvw_k+2] + 2 * __fvw_bw ))
                        if (( __fvw_y >= __fvw_rs[__fvw_k+1] && __fvw_y < __fvw_rs[__fvw_k+3] && __fvw_a <= __fvw_x2 && __fvw_x1 <= __fvw_b )); then
                            __fvw_hb[__fvw_y]=1
                            break
                        fi
                    done
                fi
                __fvw_iv[__fvw_y]=1
            done
        done
        # (a widened rectangle: its other wide rows tested at the new edges)
        for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
            if [[ -z ${__fvw_wl[__fvw_j/4]-}${__fvw_wr[__fvw_j/4]-} ]]; then continue; fi
            __fvw_x1=$(( __fvw_rs[__fvw_j] - 1 )) __fvw_x2=$(( __fvw_rs[__fvw_j+2] + 1 ))
            if [[ -z ${__fvw_wl[__fvw_j/4]-} ]]; then __fvw_x1=0; fi
            if [[ -z ${__fvw_wr[__fvw_j/4]-} ]]; then __fvw_x2=-1; fi
            __fvw_y=${__fvw_rs[__fvw_j+1]} __fvw_e=${__fvw_rs[__fvw_j+3]}
            if (( __fvw_y < 0 )); then __fvw_y=0; fi
            if (( __fvw_e > FV_SCREEN_H )); then __fvw_e=$FV_SCREEN_H; fi
            for (( ; __fvw_y < __fvw_e; __fvw_y++ )); do
                if [[ -z ${__FV_VW_WROW[__fvw_y]-} || -n ${__fvw_hb[__fvw_y]-} ]] || (( ! (${__FV_VS_WIDE[__fvw_y]:-0} & 1) )); then continue; fi
                __fvw_s=${__FV_VS_CH[__fvw_y]-}
                if { (( __fvw_x1 > 0 )) && [[ ${__fvw_s:__fvw_x1:1} == "$__FV_VS_CONT" ]]; } || { (( __fvw_x2 > 0 )) && [[ ${__fvw_s:__fvw_x2:1} == "$__FV_VS_CONT" ]]; }; then
                    __fvw_hb[__fvw_y]=1
                fi
            done
        done
        if (( ! (${#__fvw_hb[@]} + ${#__fvw_wl[@]} + ${#__fvw_wr[@]}) )); then return 0; fi
        local -n __fvw_bm=__fvw_hb
    else
        local -n __fvw_bm=__FV_VW_WROW
    fi
    # (pass 2: a rectangle is widened whole as pass 1 found (the extra cells
    # of its other rows are only repainted as they are); one with rows to
    # band is split into runs at the band edges, a run of rows to band
    # becoming one full-width band)
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        # (the rows on the screen only: nothing is drawn outside it)
        __fvw_y=${__fvw_rs[__fvw_j+1]} __fvw_e=${__fvw_rs[__fvw_j+3]}
        if (( __fvw_y < 0 )); then __fvw_y=0; fi
        if (( __fvw_e > FV_SCREEN_H )); then __fvw_e=$FV_SCREEN_H; fi
        __fvw_x1=${__fvw_rs[__fvw_j]} __fvw_x2=${__fvw_rs[__fvw_j+2]}
        if [[ -n ${__fvw_wl[__fvw_j/4]-}${__fvw_wr[__fvw_j/4]-} ]]; then
            if [[ -n ${__fvw_wl[__fvw_j/4]-} ]]; then __fvw_x1=$(( __fvw_x1 - 1 )); fi
            if [[ -n ${__fvw_wr[__fvw_j/4]-} ]] && (( __fvw_x2 < __fvw_w )); then __fvw_x2=$(( __fvw_x2 + 1 )); fi
            __FV_VW_BANDED=$(( __FV_VW_BANDED + 1 ))
        fi
        for (( __fvw_r = __fvw_y; __fvw_r < __fvw_e; __fvw_r++ )); do
            if [[ -n ${__fvw_bm[__fvw_r]-} ]]; then break; fi
        done
        if (( __fvw_r >= __fvw_e )); then
            if (( __fvw_y < __fvw_e )); then __fvw_nr+=("$__fvw_x1" "$__fvw_y" "$__fvw_x2" "$__fvw_e"); fi
            continue
        fi
        while (( __fvw_y < __fvw_e )); do
            __fvw_s=${__fvw_bm[__fvw_y]-}
            for (( __fvw_r = __fvw_y + 1; __fvw_r < __fvw_e; __fvw_r++ )); do
                if ! [ "${__fvw_bm[__fvw_r]-}" = "$__fvw_s" ]; then break; fi
            done
            if [[ -z $__fvw_s ]]; then
                __fvw_nr+=("$__fvw_x1" "$__fvw_y" "$__fvw_x2" "$__fvw_r")
            else
                # (the rows not banded yet, as one band)
                for (( __fvw_q = __fvw_y; __fvw_q < __fvw_r; __fvw_q++ )); do
                    if [[ -z ${__fvw_dn[__fvw_q]-} ]]; then break; fi
                done
                if (( __fvw_q < __fvw_r )); then
                    __fvw_nr+=(0 "$__fvw_y" "$__fvw_w" "$__fvw_r")
                    __FV_VW_BANDED=$(( __FV_VW_BANDED + 1 ))
                    for (( __fvw_q = __fvw_y; __fvw_q < __fvw_r; __fvw_q++ )); do __fvw_dn[__fvw_q]=1; done
                fi
            fi
            __fvw_y=$__fvw_r
        done
    done
    __fvw_rs=("${__fvw_nr[@]}")
}

# fv.views._wideMark — after a repaint: the rows of the caller's __fvw_rs
# that now hold wide cells (fv.video's per-row flag __FV_VS_WIDE, read as a
# friend) are marked in __FV_VW_WROW, and so is every row fv.video wrote a
# wide character into since the last look (its flag __FV_VS_WNEW, another
# friend field, cleared here): a row whose only pair a view in front hides
# by half at the first paint holds no continuation cell, yet a later repaint
# that uncovers the pair needs the edge test; a row repainted across the
# whole width with neither flag is unmarked
fv.views._wideMark() {
    # (nothing marked, no wide character written and no row of the screen
    # holds wide cells: nothing to mark or unmark; a caller IFS that joins
    # with a digit only takes the loop below)
    if (( ! (${#__FV_VW_WROW[@]} || ${#__FV_VS_WNEW[@]}) )) && [[ ${__FV_VS_WIDE[*]-} != *[123]* ]]; then return 0; fi
    # (one rectangle short of the full width, no wide character written and
    # no row of it holding wide cells: nothing to mark, nothing to unmark —
    # the rows kept marked after CJK do not take the loop on every repaint)
    if (( ! ${#__FV_VS_WNEW[@]} && ${#__fvw_rs[@]} == 4 )) && (( __fvw_rs[0] > 0 || __fvw_rs[2] < FV_SCREEN_W )); then
        local __fvw_y=${__fvw_rs[1]} __fvw_e=${__fvw_rs[3]}
        if (( __fvw_y < 0 )); then __fvw_y=0; fi
        if (( __fvw_e > FV_SCREEN_H )); then __fvw_e=$FV_SCREEN_H; fi
        if (( __fvw_e <= __fvw_y )) || [[ "${__FV_VS_WIDE[*]:__fvw_y:__fvw_e-__fvw_y}" != *[123]* ]]; then return 0; fi
    fi
    fv.views._wideMarkx
}
# fv.views._wideMarkx — fv.views._wideMark's loop
fv.views._wideMarkx() {
    local __fvw_j __fvw_y __fvw_a=$FV_SCREEN_H __fvw_b=0
    local -a __fvw_full=()
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        if (( __fvw_rs[__fvw_j+1] < __fvw_a )); then __fvw_a=${__fvw_rs[__fvw_j+1]}; fi
        if (( __fvw_rs[__fvw_j+3] > __fvw_b )); then __fvw_b=${__fvw_rs[__fvw_j+3]}; fi
        if (( __fvw_rs[__fvw_j] <= 0 && __fvw_rs[__fvw_j+2] >= FV_SCREEN_W )); then
            for (( __fvw_y = __fvw_rs[__fvw_j+1]; __fvw_y < __fvw_rs[__fvw_j+3]; __fvw_y++ )); do __fvw_full[__fvw_y]=1; done
        fi
    done
    if (( __fvw_a < 0 )); then __fvw_a=0; fi
    if (( __fvw_b > FV_SCREEN_H )); then __fvw_b=$FV_SCREEN_H; fi
    for (( __fvw_y = __fvw_a; __fvw_y < __fvw_b; __fvw_y++ )); do
        if (( ${__FV_VS_WIDE[__fvw_y]:-0} )); then __FV_VW_WROW[__fvw_y]=1
        elif [[ -n ${__fvw_full[__fvw_y]-} ]]; then unset '__FV_VW_WROW[__fvw_y]'; fi
    done
    if (( ${#__FV_VS_WNEW[@]} )); then
        for __fvw_y in "${!__FV_VS_WNEW[@]}"; do __FV_VW_WROW[__fvw_y]=1; done
        __FV_VS_WNEW=()
    fi
}

# fv.views._drawView V — FV DrawView (+ DrawShow's shadow): when V may be
# drawn, paint V, shade its shadow, the views in front over S(V), flush.
# Nested inside a Draw: what lies under a covering view in that Draw is left
# out (fv.views._nestCut); rows with wide cells are banded (fv.views._bands)
fv.views._drawView() {
    fv.views._drawable "$1" || return 0
    local __fvw_bg __fvw_b1 __fvw_b2 __fvw_b3 __fvw_b4 __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4 __fvw_j
    fv.views._srect "$1"
    # (D21: S(V) cut to the owner's clip: neither V nor its shadow reaches past it)
    local -n __fvw_vo=${1}_data
    local __fvw_ow=${__fvw_vo[Owner]-}
    if [[ -n $__fvw_ow ]]; then
        if (( __fvw_r1 < __FV_VW_C1[$__fvw_ow] )); then __fvw_r1=${__FV_VW_C1[$__fvw_ow]}; fi
        if (( __fvw_r2 < __FV_VW_C2[$__fvw_ow] )); then __fvw_r2=${__FV_VW_C2[$__fvw_ow]}; fi
        if (( __fvw_r3 > __FV_VW_C3[$__fvw_ow] )); then __fvw_r3=${__FV_VW_C3[$__fvw_ow]}; fi
        if (( __fvw_r4 > __FV_VW_C4[$__fvw_ow] )); then __fvw_r4=${__FV_VW_C4[$__fvw_ow]}; fi
        # (nothing inside the owner's clip: no drawing, but a held frame or a
        # pending forced update still goes out, as the full path's flush does)
        if (( __fvw_r1 >= __fvw_r3 || __fvw_r2 >= __fvw_r4 )); then fv.views._flush; return 0; fi
    fi
    local -a __fvw_rs=("$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4")
    if (( ${#__FV_VW_INDRAW[@]} )); then fv.views._nestCut "$1"; fi
    if (( ${#__FV_VW_WROW[@]} )); then fv.views._bands; fi
    fv.views._begin
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        fv.views._paint "$1" "${__fvw_rs[@]:__fvw_j:4}"
        fv.views._shade "$1" "${__fvw_rs[@]:__fvw_j:4}" || :
    done
    fv.views._over "$1"
    if (( ${#__FV_VW_WROW[@]} || ${#__FV_VS_WNEW[@]} )) || [[ ${__FV_VS_WIDE[*]-} == *[123]* ]]; then fv.views._wideMark; fi
    fv.views._end
    fv.views._flush
}

# fv.views._drawUnder G X1 Y1 X2 Y2 — FV DrawUnderRect: the rectangle ∩ G's
# clip (only that can have changed: G's subviews and their shadows are clipped
# to it) repainted from below. A group that does not cover its rect (a
# frameless group) leaves its uncovered cells to the views behind it, so the
# repaint starts at the first owner that covers (a framed group) or at the
# root: that group painted clipped to the rectangle, then the views in front
# of it over it, flush
fv.views._drawUnder() {
    fv.views._drawable "$1" || return 0
    local __fvw_bg __fvw_b1 __fvw_b2 __fvw_b3 __fvw_b4 __fvw_g=$1 __fvw_j
    local __fvw_1=$2 __fvw_2=$3 __fvw_3=$4 __fvw_4=$5
    if (( __FV_VW_C1[$1] > __fvw_1 )); then __fvw_1=${__FV_VW_C1[$1]}; fi
    if (( __FV_VW_C2[$1] > __fvw_2 )); then __fvw_2=${__FV_VW_C2[$1]}; fi
    if (( __FV_VW_C3[$1] < __fvw_3 )); then __fvw_3=${__FV_VW_C3[$1]}; fi
    if (( __FV_VW_C4[$1] < __fvw_4 )); then __fvw_4=${__FV_VW_C4[$1]}; fi
    if (( __fvw_1 >= __fvw_3 || __fvw_2 >= __fvw_4 )); then return 0; fi
    while ! fv.views._covers "$__fvw_g"; do
        local -n __fvw_gd=${__fvw_g}_data
        if [[ -z ${__fvw_gd[Owner]-} ]]; then break; fi
        __fvw_g=${__fvw_gd[Owner]}
    done
    local -a __fvw_rs=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4")
    if (( ${#__FV_VW_WROW[@]} )); then fv.views._bands 1; fi
    fv.views._begin
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        fv.views._paint "$__fvw_g" "${__fvw_rs[@]:__fvw_j:4}"
    done
    fv.views._over "$__fvw_g"
    if (( ${#__FV_VW_WROW[@]} || ${#__FV_VS_WNEW[@]} )) || [[ ${__FV_VS_WIDE[*]-} == *[123]* ]]; then fv.views._wideMark; fi
    fv.views._end
    fv.views._flush
}

# fv.views._overOnly V X1 Y1 X2 Y2 — only the views in front of V over the
# rectangle, flush (V moved behind views that overlap it)
fv.views._overOnly() {
    fv.views._drawable "$1" || return 0
    local __fvw_bg __fvw_b1 __fvw_b2 __fvw_b3 __fvw_b4
    local -a __fvw_rs=("$2" "$3" "$4" "$5")
    if (( ${#__FV_VW_WROW[@]} )); then fv.views._bands 1; fi
    fv.views._begin
    fv.views._over "$1"
    if (( ${#__FV_VW_WROW[@]} || ${#__FV_VS_WNEW[@]} )) || [[ ${__FV_VS_WIDE[*]-} == *[123]* ]]; then fv.views._wideMark; fi
    fv.views._end
    fv.views._flush
}

# ---- the public drawing API (FV DrawView, Redraw, Show, Hide, Lock, Unlock,
# LockScreenUpdate, UnlockScreenUpdate; drawPart) -------------------------------

# fv.views.drawView V — FV DrawView: V drawn in place with its shadow, the
# views in front of it over it, the terminal updated (unless held). Nothing
# for a V that is hidden, has a hidden or locked owner, or whose tree's root
# lacks sfExposed
fv.views.drawView() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" drawView || return
    local __fvw_r=${RESULT-}
    fv.views._drawView "$1"
    RESULT=$__fvw_r
}

# fv.views.redraw V — FV Redraw: as drawView, with a forced terminal update
# (every cell sent again); while the update is held (lockScreenUpdate, a user
# lock, another drawing entry) the force waits for the release
fv.views.redraw() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" redraw || return
    local __fvw_r=${RESULT-}
    __FV_VW_FORCE=1
    if fv.views._drawable "$1"; then fv.views._drawView "$1"; else fv.views._flush; fi
    RESULT=$__fvw_r
}

# fv.views.drawPart V FN Y1 Y2 [ARGS] — partial redraw of a LEAF (rule 4):
# the plain painter FN runs as `FN V ARGS` with V's drawing context, its
# writes clipped to V's local rows Y1 <= y < Y2; then the views in front of V
# that overlap those rows are painted again over them, and the terminal is
# updated. No dispatch. A group is refused (rc 2): its painter would write
# over its own subviews. Nested inside a Draw, the part under a covering view
# in that Draw is left out (FN may then run once per remaining piece). rc:
# FN's (the last non-zero one; 0 when V cannot be drawn now: FN does not run)
fv.views.drawPart() {
    # (D21 fast path, one test: a live leaf, a painter seen before, rows of
    # 1-9 plain digits, not nested in a Draw; the rest, and every refusal,
    # take the checked path)
    if (( $# < 4 )) || [[ -z $1 || -z $2 || -z ${__FV_VW_LIVE[$1]-} || -n ${__FV_VW_GRP[$1]-} || -z ${__FV_VW_PNT[$2]-} \
          || $3$4 == *[!0123456789]* || ${#3}${#4} != [123456789][123456789] ]] || (( ${#__FV_VW_INDRAW[@]} )); then
        fv.views._drawPartX "$@"; return
    fi
    fv.views._drawable "$1" || return 0
    local __fvw_r=${RESULT-} __fvw_s=0 __fvw_1=${__FV_VW_C1[$1]} __fvw_2=$(( __FV_VW_AY[$1] + 10#$3 )) __fvw_3=${__FV_VW_C3[$1]} __fvw_4=$(( __FV_VW_AY[$1] + 10#$4 ))
    if (( __fvw_2 < __FV_VW_C2[$1] )); then __fvw_2=${__FV_VW_C2[$1]}; fi
    if (( __fvw_4 > __FV_VW_C4[$1] )); then __fvw_4=${__FV_VW_C4[$1]}; fi
    if (( __fvw_1 >= __fvw_3 || __fvw_2 >= __fvw_4 )); then return 0; fi
    local __fvw_sv=$FV_DRAW_VIEW __fvw_sx=$FV_DRAW_X __fvw_sy=$FV_DRAW_Y __fvw_sp=$FV_DRAW_PAL
    local __fvw_c1=$FV_CLIP_X1 __fvw_c2=$FV_CLIP_Y1 __fvw_c3=$FV_CLIP_X2 __fvw_c4=$FV_CLIP_Y2
    local __fvw_bg=$__FV_VW_INGRP __fvw_b1=$__FV_VW_P1 __fvw_b2=$__FV_VW_P2 __fvw_b3=$__FV_VW_P3 __fvw_b4=$__FV_VW_P4
    local -a __fvw_rs=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4")
    # (rows with wide cells: the edge test before the painter writes; the
    # views in front go over the bands it makes)
    if (( ${#__FV_VW_WROW[@]} )); then fv.views._bands; fi
    # (fv.views._begin, inline)
    if (( __FV_VW_DEPTH == 0 )); then
        if (( ${__FV_VS_H:-0} )); then __FV_VW_UCLIP=1 __FV_VW_U1=$__FV_VS_CX1 __FV_VW_U2=$__FV_VS_CY1 __FV_VW_U3=$__FV_VS_CX2 __FV_VW_U4=$__FV_VS_CY2
        else __FV_VW_UCLIP=''; fi
    fi
    if [[ -z ${__FV_VW_PAL[$1]+x} ]]; then fv.views._pal "$1"; fi
    __FV_VW_DEPTH=$(( __FV_VW_DEPTH + 1 )) __FV_VW_INGRP=0 __FV_VW_INDRAW[$1]=1
    FV_DRAW_VIEW=$1 FV_DRAW_X=${__FV_VW_AX[$1]} FV_DRAW_Y=${__FV_VW_AY[$1]} FV_DRAW_PAL=${__FV_VW_PAL[$1]}
    FV_CLIP_X1=$(( __fvw_1 - FV_DRAW_X )) FV_CLIP_Y1=$(( __fvw_2 - FV_DRAW_Y )) FV_CLIP_X2=$(( __fvw_3 - FV_DRAW_X )) FV_CLIP_Y2=$(( __fvw_4 - FV_DRAW_Y ))
    __FV_VW_P1=$__fvw_1 __FV_VW_P2=$__fvw_2 __FV_VW_P3=$__fvw_3 __FV_VW_P4=$__fvw_4
    fv.video._clipf "$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4"
    if (( $# > 4 )); then "$2" "$1" "${@:5}" || __fvw_s=$?; else "$2" "$1" || __fvw_s=$?; fi
    unset '__FV_VW_INDRAW[$1]'
    FV_DRAW_VIEW=$__fvw_sv FV_DRAW_X=$__fvw_sx FV_DRAW_Y=$__fvw_sy FV_DRAW_PAL=$__fvw_sp
    FV_CLIP_X1=$__fvw_c1 FV_CLIP_Y1=$__fvw_c2 FV_CLIP_X2=$__fvw_c3 FV_CLIP_Y2=$__fvw_c4
    __FV_VW_INGRP=1
    fv.views._over "$1"
    if (( ${#__FV_VW_WROW[@]} || ${#__FV_VS_WNEW[@]} )) || [[ ${__FV_VS_WIDE[*]-} == *[123]* ]]; then fv.views._wideMark; fi
    fv.views._end
    # (fv.views._flush, inline for the held case: inside an event handler)
    if (( __FV_VW_LSU || __FV_VW_LOCKN )); then
        if (( __FV_VW_DEPTH == 0 )); then __FV_VW_PEND=1; fi
    else fv.views._flush; fi
    RESULT=$__fvw_r
    return "$__fvw_s"
}
# fv.views._drawPartX — drawPart's checked path (the first call with a
# painter, rows other than plain digits, a nested draw, wide rows)
fv.views._drawPartX() {
    if (( $# < 4 )); then fv.views._bad drawPart 'wrong argument count'; return; fi
    fv.views._view "$1" drawPart || return
    if [[ -n ${__FV_VW_GRP[$1]-} ]]; then fv.views._bad drawPart "'$1' is a group: drawPart paints a leaf (redraw a group with drawView)"; return; fi
    if ! declare -F "$2" >/dev/null; then fv.views._bad drawPart "'$2' is not a function"; return; fi
    __FV_VW_PNT[$2]=1
    local -a __fvw_v
    # (rows of 1-9 plain digits without a call; anything else: _ints)
    if [[ $3$4 != *[!0123456789]* && ${#3}${#4} == [123456789][123456789] ]]; then __fvw_v=("$(( 10#$3 ))" "$(( 10#$4 ))")
    elif ! fv.views._ints "$3" "$4"; then fv.views._bad drawPart 'Y1 Y2 must be integers'; return; fi
    local __fvw_r=${RESULT-} __fvw_s=0 __fvw_j __fvw_e=0
    if ! fv.views._drawable "$1"; then return 0; fi
    if [[ -n ${__FV_VW_INDRAW[$1]-} ]]; then return 0; fi
    local __fvw_1=${__FV_VW_C1[$1]} __fvw_2=$(( __FV_VW_AY[$1] + __fvw_v[0] )) __fvw_3=${__FV_VW_C3[$1]} __fvw_4=$(( __FV_VW_AY[$1] + __fvw_v[1] ))
    if (( __fvw_2 < __FV_VW_C2[$1] )); then __fvw_2=${__FV_VW_C2[$1]}; fi
    if (( __fvw_4 > __FV_VW_C4[$1] )); then __fvw_4=${__FV_VW_C4[$1]}; fi
    if (( __fvw_1 >= __fvw_3 || __fvw_2 >= __fvw_4 )); then return 0; fi
    local __fvw_bg __fvw_b1 __fvw_b2 __fvw_b3 __fvw_b4
    local __fvw_sv=$FV_DRAW_VIEW __fvw_sx=$FV_DRAW_X __fvw_sy=$FV_DRAW_Y __fvw_sp=$FV_DRAW_PAL
    local __fvw_c1=$FV_CLIP_X1 __fvw_c2=$FV_CLIP_Y1 __fvw_c3=$FV_CLIP_X2 __fvw_c4=$FV_CLIP_Y2
    local -a __fvw_rs=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4")
    if (( ${#__FV_VW_INDRAW[@]} )); then fv.views._nestCut "$1"; fi
    if (( ! ${#__fvw_rs[@]} )); then return 0; fi
    # (rows with wide cells: the edge test before the painter writes, its
    # bands kept for the views in front)
    local -a __fvw_ro=() __fvw_rb=()
    if (( ${#__FV_VW_WROW[@]} )); then __fvw_ro=("${__fvw_rs[@]}"); fv.views._bands; __fvw_rb=("${__fvw_rs[@]}") __fvw_rs=("${__fvw_ro[@]}"); fi
    fv.views._begin
    if [[ -z ${__FV_VW_PAL[$1]+x} ]]; then fv.views._pal "$1"; fi
    FV_DRAW_VIEW=$1 FV_DRAW_X=${__FV_VW_AX[$1]} FV_DRAW_Y=${__FV_VW_AY[$1]} FV_DRAW_PAL=${__FV_VW_PAL[$1]}
    __FV_VW_INGRP=0 __FV_VW_INDRAW[$1]=1
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        __fvw_1=${__fvw_rs[__fvw_j]} __fvw_2=${__fvw_rs[__fvw_j+1]} __fvw_3=${__fvw_rs[__fvw_j+2]} __fvw_4=${__fvw_rs[__fvw_j+3]}
        FV_CLIP_X1=$(( __fvw_1 - FV_DRAW_X )) FV_CLIP_Y1=$(( __fvw_2 - FV_DRAW_Y ))
        FV_CLIP_X2=$(( __fvw_3 - FV_DRAW_X )) FV_CLIP_Y2=$(( __fvw_4 - FV_DRAW_Y ))
        __FV_VW_P1=$__fvw_1 __FV_VW_P2=$__fvw_2 __FV_VW_P3=$__fvw_3 __FV_VW_P4=$__fvw_4
        fv.video._clipf "$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4"
        __fvw_e=0
        if (( $# > 4 )); then "$2" "$1" "${@:5}" || __fvw_e=$?; else "$2" "$1" || __fvw_e=$?; fi
        if (( __fvw_e )); then __fvw_s=$__fvw_e; fi
    done
    unset '__FV_VW_INDRAW[$1]'
    FV_DRAW_VIEW=$__fvw_sv FV_DRAW_X=$__fvw_sx FV_DRAW_Y=$__fvw_sy FV_DRAW_PAL=$__fvw_sp
    FV_CLIP_X1=$__fvw_c1 FV_CLIP_Y1=$__fvw_c2 FV_CLIP_X2=$__fvw_c3 FV_CLIP_Y2=$__fvw_c4
    __FV_VW_INGRP=1
    if (( ${#__fvw_ro[@]} )); then __fvw_rs=("${__fvw_rb[@]}"); fi
    fv.views._over "$1"
    if (( ${#__FV_VW_WROW[@]} || ${#__FV_VS_WNEW[@]} )) || [[ ${__FV_VS_WIDE[*]-} == *[123]* ]]; then fv.views._wideMark; fi
    fv.views._end
    fv.views._flush
    RESULT=$__fvw_r
    return "$__fvw_s"
}

# fv.views.show V / hide V — FV Show / Hide: V's SetState(sfVisible, …)
# through the elision when the bit is not so yet (a no-op otherwise); TView's
# body sets the bit, then (V in a group) FV's DrawShow (drawView V with its
# shadow) / DrawHide (drawUnder the owner over S(V)), then the owner's
# ResetCurrent for a selectable V. RESULT is kept
fv.views.show() { fv.views._showHide "${1-}" 1 show "$#"; }
fv.views.hide() { fv.views._showHide "${1-}" 0 hide "$#"; }
fv.views._showHide() {   # V ON CALLER ARGC
    if (( $4 != 1 )); then fv.views._bad "$3" 'wrong argument count'; return; fi
    fv.views._view "$1" "$3" || return
    local -n __fvw_d=${1}_data
    if (( $2 )); then
        if (( ${__fvw_d[State]:-0} & FV_SF_VISIBLE )); then return 0; fi
    else
        if (( ! (${__fvw_d[State]:-0} & FV_SF_VISIBLE) )); then return 0; fi
    fi
    # FV Show / Hide: SetState(sfVisible, ...), a virtual (its body draws)
    fv.views._virt "$1" SetState "$FV_SF_VISIBLE" "$2" || :
}

# fv.views.lock G / unlock G — FV TGroup.Lock / Unlock (the LockFlag count):
# while G is locked, no drawView of G or of a view inside it is drawn (the
# hooks' redraws included) and the terminal update is held; when its count
# returns to 0, G is redrawn once (FV Unlock -> DrawView; when an owner of G
# is still locked, that owner's unlock draws it). unlock of an unlocked
# group: a no-op
fv.views.lock() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" lock || return
    local -n __fvw_d=${1}_data
    __FV_VW_LK[$1]=$(( ${__FV_VW_LK[$1]:-0} + 1 ))
    __fvw_d[LockFlag]=${__FV_VW_LK[$1]}
    __FV_VW_LOCKN=$(( __FV_VW_LOCKN + 1 ))
}
fv.views.unlock() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" unlock || return
    if [[ -z ${__FV_VW_LK[$1]-} ]]; then return 0; fi
    local -n __fvw_d=${1}_data
    local __fvw_r=${RESULT-}
    __FV_VW_LOCKN=$(( __FV_VW_LOCKN - 1 ))
    if (( __FV_VW_LOCKN < 0 )); then __FV_VW_LOCKN=0; fi
    if (( ${__FV_VW_LK[$1]} > 1 )); then
        __FV_VW_LK[$1]=$(( ${__FV_VW_LK[$1]} - 1 ))
        __fvw_d[LockFlag]=${__FV_VW_LK[$1]}
        return 0
    fi
    unset '__FV_VW_LK[$1]'
    __fvw_d[LockFlag]=0
    if fv.views._drawable "$1"; then fv.views._drawView "$1"; else fv.views._flush; fi
    RESULT=$__fvw_r
}

# fv.views.lockScreenUpdate / unlockScreenUpdate — FV LockScreenUpdate /
# UnlockScreenUpdate: hold the terminal update (a count); the drawing into
# the buffer goes on. At 0 again, unlockScreenUpdate updates the terminal
# (unless a user lock still holds it); unlockScreenUpdate at 0: a no-op
fv.views.lockScreenUpdate() {
    if (( $# )); then fv.views._bad "${FUNCNAME#fv.views.}" 'no arguments'; return; fi
    __FV_VW_LSU=$(( __FV_VW_LSU + 1 ))
}
fv.views.unlockScreenUpdate() {
    if (( $# )); then fv.views._bad "${FUNCNAME#fv.views.}" 'no arguments'; return; fi
    if (( __FV_VW_LSU == 0 )); then return 0; fi
    # (an unlock without its lock inside a modal handler: the loop's own
    # holds (__FV_VW_EH) are not the caller's to release)
    if (( __FV_VW_LSU <= __FV_VW_EH )); then kk.debug "Error: fv.views.unlockScreenUpdate: no lockScreenUpdate of yours to release (ignored)"; return 0; fi
    local __fvw_r=${RESULT-}
    __FV_VW_LSU=$(( __FV_VW_LSU - 1 ))
    if (( __FV_VW_LSU == 0 )) && [[ -n $__FV_VW_CPEND ]]; then fv.views._cursorNow; fi
    fv.views._flush
    RESULT=$__fvw_r
}

# ---- palettes (design §1.9) ------------------------------------------------------

# fv.views._pal V — resolve V's palette into __FV_VW_PAL[V] (FV GetColor's
# owner walk, done once): V's GetPalette (a func, through the elision) is a
# list of indices into its owner's resolved palette ('' = none: V maps as
# its owner does); the root maps into the app palette __FV_VW_APAL. An index
# that is 0, not a number or past the palette below gives ErrorAttr's
# symbol (__FV_VW_ERRSYM). RESULT is kept.
fv.views._pal() {
    local -n __fvw_d=${1}_data
    local __fvw_o=${__fvw_d[Owner]-} __fvw_b __fvw_r=${RESULT-} __fvw_p='' __fvw_n __fvw_i
    if [[ -n $__fvw_o ]]; then
        if [[ -z ${__FV_VW_PAL[$__fvw_o]+x} ]]; then fv.views._pal "$__fvw_o"; fi
        __fvw_b=${__FV_VW_PAL[$__fvw_o]}
    else
        __fvw_b=$__FV_VW_APAL
    fi
    RESULT=''
    fv.views._virt "$1" GetPalette || RESULT=''
    if [[ -z ${RESULT-} ]]; then __FV_VW_PAL[$1]=$__fvw_b; RESULT=$__fvw_r; return 0; fi
    local -a __fvw_a
    # (as `read -r -a` with IFS=' ' did: the first line, split at blanks, no globbing)
    local - IFS=' '
    set -f
    __fvw_a=(${RESULT%%$'\n'*})
    for __fvw_n in "${__fvw_a[@]}"; do
        if [[ $__fvw_n == *[!0123456789]* || ${#__fvw_n} -gt 4 ]]; then __fvw_p+=$__FV_VW_ERRSYM; continue; fi
        __fvw_i=$(( 10#$__fvw_n ))
        if (( __fvw_i >= 1 && __fvw_i <= ${#__fvw_b} )); then __fvw_p+=${__fvw_b:__fvw_i-1:1}; else __fvw_p+=$__FV_VW_ERRSYM; fi
    done
    __FV_VW_PAL[$1]=$__fvw_p
    RESULT=$__fvw_r
}

# fv.views._palReset V — drop the resolved palette of V and its subtree
fv.views._palReset() {
    unset '__FV_VW_PAL[$1]'
    if [[ -n ${__FV_VW_GRP[$1]-} ]]; then
        local -n __fvw_pl=${1}_views
        local __fvw_k
        for __fvw_k in "${__fvw_pl[@]}"; do fv.views._palReset "$__fvw_k"; done
    fi
}

# fv.views.resetPalette [V] — forget resolved palettes (V's subtree, or every
# view): after a GetPalette answer changed (a TWindow's Palette field, an
# override of yours) or the app palette did (fv.app's setAppPalette). They
# are resolved again at the next draw; nothing is redrawn here
fv.views.resetPalette() {
    if (( $# > 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    if (( $# == 0 )); then __FV_VW_PAL=(); return 0; fi
    fv.views._view "$1" resetPalette || return
    fv.views._palReset "$1"
}

# fv.views.getColor V I — FV GetColor(I): RESULT = the fv.video symbol of
# V's palette entry I (1-based), ErrorAttr's symbol for an index outside it.
# Inside a Draw the same is ${FV_DRAW_PAL:I-1:1}
fv.views.getColor() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" getColor || return
    if [[ -z $2 || $2 == *[!0123456789]* || ${#2} -gt 4 ]]; then fv.views._bad getColor 'I must be a palette index (digits)'; return; fi
    if [[ -z ${__FV_VW_PAL[$1]+x} ]]; then fv.views._pal "$1"; fi
    local __fvw_p=${__FV_VW_PAL[$1]} __fvw_i=$(( 10#$2 ))
    if (( __fvw_i >= 1 && __fvw_i <= ${#__fvw_p} )); then RESULT=${__fvw_p:__fvw_i-1:1}; else RESULT=$__FV_VW_ERRSYM; fi
}

# ---- the writers (design §1.5): view-local coordinates, one fv.video call ------
# Only inside a Draw or a drawPart painter (FV_DRAW_VIEW set; else rc 2);
# COLOR is an index into the view's palette (FV WriteStr's Color);
# RESULT = fv.video's answer (the cells the write advances), rc = its rc.
# Writes are clipped to the part of the view the paint may change; FV writes
# update the terminal at once, these leave it to the drawing entry.

# fv.views._wxy X Y CALLER — the caller's __fvw_x / __fvw_y = the absolute
# point; rc 2 (fv.views._bad) outside a Draw or for a non-integer
fv.views._wxy() {
    if [[ -z $FV_DRAW_VIEW ]]; then fv.views._bad "$3" 'outside a Draw (draw through drawView / drawPart)'; return; fi
    local __fvw_a=${1#-} __fvw_b=${2#-}
    if [[ -z $__fvw_a || $__fvw_a == *[!0123456789]* || ${#__fvw_a} -gt 7 \
          || -z $__fvw_b || $__fvw_b == *[!0123456789]* || ${#__fvw_b} -gt 7 ]]; then
        fv.views._bad "$3" 'X Y must be integers'; return
    fi
    if [[ $1 == -* ]]; then __fvw_x=$(( FV_DRAW_X - 10#$__fvw_a )); else __fvw_x=$(( FV_DRAW_X + 10#$__fvw_a )); fi
    if [[ $2 == -* ]]; then __fvw_y=$(( FV_DRAW_Y - 10#$__fvw_b )); else __fvw_y=$(( FV_DRAW_Y + 10#$__fvw_b )); fi
}
# fv.views._wcol I CALLER — the caller's __fvw_c = palette entry I's symbol
# (ErrorAttr's outside the palette); rc 2 for a non-index
fv.views._wcol() {
    if [[ -z $1 || $1 == *[!0123456789]* || ${#1} -gt 4 ]]; then fv.views._bad "$2" 'COLOR must be a palette index'; return; fi
    local __fvw_i=$(( 10#$1 ))
    if (( __fvw_i >= 1 && __fvw_i <= ${#FV_DRAW_PAL} )); then __fvw_c=${FV_DRAW_PAL:__fvw_i-1:1}; else __fvw_c=$__FV_VW_ERRSYM; fi
}

# Each writer first tries the fast path: inside a Draw, X and Y plain digits
# (1-7), COLOR 1-99 within the palette, the right count -> one arithmetic
# step and the fv.video call; anything else (negative coordinates, an index
# outside the palette, an error) takes the checked path below.

# fv.views.writeStr X Y TEXT COLOR — FV WriteStr
fv.views.writeStr() {
    if (( $# == 4 )) && [[ -n $FV_DRAW_VIEW && $1$2 != *[!0123456789]* && ${#1}${#2} == [1234567][1234567] ]]; then
        if [[ ${4-} == [123456789] || ${4-} == [123456789][0123456789] ]] && (( $4 <= ${#FV_DRAW_PAL} )); then
            fv.video._wstr "$(( FV_DRAW_X + 10#$1 ))" "$(( FV_DRAW_Y + 10#$2 ))" "$3" "${FV_DRAW_PAL:$4-1:1}"
            return
        fi
    fi
    if (( $# != 4 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    local __fvw_x __fvw_y __fvw_c
    fv.views._wxy "$1" "$2" writeStr || return
    fv.views._wcol "$4" writeStr || return
    fv.video.writeStr "$__fvw_x" "$__fvw_y" "$3" "$__fvw_c"
}
# fv.views.writeChar X Y CH COLOR [COUNT] — FV WriteChar (COUNT default 1)
fv.views.writeChar() {
    if (( $# == 4 || $# == 5 )) && [[ -n $FV_DRAW_VIEW && $1$2 != *[!0123456789]* && ${#1}${#2} == [1234567][1234567] ]]; then
        if [[ ${4-} == [123456789] || ${4-} == [123456789][0123456789] ]] && (( $4 <= ${#FV_DRAW_PAL} )); then
            fv.video.writeChar "$(( FV_DRAW_X + 10#$1 ))" "$(( FV_DRAW_Y + 10#$2 ))" "$3" "${FV_DRAW_PAL:$4-1:1}" "${5:-1}"
            return
        fi
    fi
    if (( $# != 4 && $# != 5 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    local __fvw_x __fvw_y __fvw_c
    fv.views._wxy "$1" "$2" writeChar || return
    fv.views._wcol "$4" writeChar || return
    fv.video.writeChar "$__fvw_x" "$__fvw_y" "$3" "$__fvw_c" "${5:-1}"
}
# fv.views.writeCStr X Y TEXT C1 C2 — FV MoveCStr + WriteLine: each `~`
# switches between the palette entries C1 and C2 (FV's Word Lo / Hi)
fv.views.writeCStr() {
    if (( $# != 5 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    local __fvw_x __fvw_y __fvw_c __fvw_c1
    fv.views._wxy "$1" "$2" writeCStr || return
    fv.views._wcol "$4" writeCStr || return
    __fvw_c1=$__fvw_c
    fv.views._wcol "$5" writeCStr || return
    fv.video.writeCStr "$__fvw_x" "$__fvw_y" "$3" "$__fvw_c1" "$__fvw_c"
}
# fv.views.writeLine X Y H TEXT ATTRS — FV WriteLine(X, Y, W, H, Buf): the row
# TEXT with the RESOLVED symbols ATTRS (one per display cell, as FV's
# TDrawBuffer holds resolved attributes: build them with getColor /
# FV_DRAW_PAL) on the H rows Y .. Y+H-1 (fv.video.writeBuf's repeat count)
fv.views.writeLine() {
    if (( $# == 5 )) && [[ -n $FV_DRAW_VIEW && $1$2 != *[!0123456789]* && ${#1}${#2} == [1234567][1234567] ]]; then
        fv.video.writeBuf "$(( FV_DRAW_X + 10#$1 ))" "$(( FV_DRAW_Y + 10#$2 ))" "$4" "$5" "$3"
        return
    fi
    if (( $# != 5 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    local __fvw_x __fvw_y
    fv.views._wxy "$1" "$2" writeLine || return
    fv.video.writeBuf "$__fvw_x" "$__fvw_y" "$4" "$5" "$3"
}
# fv.views.writeLines X Y TEXTS ATTRS — (D21 stage E) many rows in one call:
# TEXTS and ATTRS are names of two indexed arrays; for every index k of
# TEXTS, in order, the row TEXTS[k] with the RESOLVED symbols ATTRS[k] at
# view row Y+k, exactly as `writeLine X Y+k 1 TEXTS[k] ATTRS[k]` (a sparse
# TEXTS skips rows; a missing ATTRS[k] is ''). One fv.video call for all the
# rows (fv.video._wrows). RESULT = the widest row's cells advanced (writeLine's
# answer, the maximum over the rows; 0 for no rows); rc 2 with RESULT '' for
# a malformed call (nothing written: the count, outside a Draw, X / Y not
# integers, a name that is no identifier, starts with __fv or is RESULT, an
# associative array) and after the rows when a row is refused (the rows
# writeLine refuses: symbols not fv.video's, ATTRS not as long as the text).
# The names are checked by fv.video._wrows (its rc 3, reported here): the
# common call is as thin as writeLine's
fv.views.writeLines() {
    if (( $# == 4 )) && [[ -n $FV_DRAW_VIEW && $1$2 != *[!0123456789]* && ${#1}${#2} == [1234567][1234567] ]]; then
        fv.video._wrows "$(( FV_DRAW_X + 10#$1 ))" "$(( FV_DRAW_Y + 10#$2 ))" "$3" "$4" || fv.views._wlrc "$?"
        return
    fi
    if (( $# != 4 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    local __fvw_x __fvw_y
    fv.views._wxy "$1" "$2" writeLines || return
    fv.video._wrows "$__fvw_x" "$__fvw_y" "$3" "$4" || fv.views._wlrc "$?"
}
# fv.views._wlrc RC — writeLines' answer for fv.video._wrows' rc: 3 (a name
# refused) -> the refusal (rc 2, RESULT '', the debug line), else RC
fv.views._wlrc() {
    if (( $1 == 3 )); then fv.views._bad writeLines 'TEXTS ATTRS must be names of indexed arrays (identifiers; not __fv*, not RESULT)'; return; fi
    return "$1"
}
# fv.views.writeRows X Y W TEXTS SYMS — (P3 10.2) uniform-symbol rows: for
# every index k of the indexed array named TEXTS, in order, the row TEXTS[k]
# in the ONE resolved symbol SYMS[k] at view row Y+k, cut or padded to W
# cells by fv.video's own cells (a wide character the cut halves becomes a
# space; a short row is padded with spaces) — a list row with wide text
# without a width call per row. One fv.video call (fv.video._wrowsu).
# RESULT = W (0 for no rows or W 0); rc 2 with RESULT '' for a malformed call
# (nothing written: the count, outside a Draw, X / Y / W not integers or W
# negative, the names as writeLines') and after the rows when a row is
# refused (SYMS[k] not one fv.video symbol)
fv.views.writeRows() {
    if (( $# == 5 )) && [[ -n $FV_DRAW_VIEW && $1$2$3 != *[!0123456789]* && ${#1}${#2}${#3} == [1234567][1234567][1234567] ]]; then
        fv.video._wrowsu "$(( FV_DRAW_X + 10#$1 ))" "$(( FV_DRAW_Y + 10#$2 ))" "$(( 10#$3 ))" "$4" "$5" || fv.views._wrrc "$?"
        return
    fi
    if (( $# != 5 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    local __fvw_x __fvw_y
    fv.views._wxy "$1" "$2" writeRows || return
    if [[ -z $3 || $3 == *[!0123456789]* || ${#3} -gt 7 ]]; then fv.views._bad writeRows 'W must be an integer >= 0'; return; fi
    fv.video._wrowsu "$__fvw_x" "$__fvw_y" "$(( 10#$3 ))" "$4" "$5" || fv.views._wrrc "$?"
}
# fv.views._wrrc RC — writeRows' answer for fv.video._wrowsu's rc (as _wlrc)
fv.views._wrrc() {
    if (( $1 == 3 )); then fv.views._bad writeRows 'TEXTS SYMS must be names of indexed arrays (identifiers; not __fv*, not RESULT)'; return; fi
    return "$1"
}
# fv.views.fill X Y W H CH COLOR — the rectangle filled with CH's first
# cluster in palette entry COLOR (FV MoveChar + WriteLine with H rows)
fv.views.fill() {
    if (( $# == 6 )) && [[ -n $FV_DRAW_VIEW && $1$2 != *[!0123456789]* && ${#1}${#2} == [1234567][1234567] ]]; then
        if [[ ${6-} == [123456789] || ${6-} == [123456789][0123456789] ]] && (( $6 <= ${#FV_DRAW_PAL} )); then
            fv.video.fillRect "$(( FV_DRAW_X + 10#$1 ))" "$(( FV_DRAW_Y + 10#$2 ))" "$3" "$4" "${FV_DRAW_PAL:$6-1:1}" "$5"
            return
        fi
    fi
    if (( $# != 6 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    local __fvw_x __fvw_y __fvw_c
    fv.views._wxy "$1" "$2" fill || return
    fv.views._wcol "$6" fill || return
    fv.video.fillRect "$__fvw_x" "$__fvw_y" "$3" "$4" "$__fvw_c" "$5"
}

# ---- the built-in Draw / GetPalette bodies -----------------------------------------
# A Draw body draws only as the painter's current view (FV_DRAW_VIEW = V):
# calling V.Draw outside the painter draws nothing (draw with drawView).

# TView.Draw — FV: blanks in colour 1 over the whole view (one fill)
fv.views._viewDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fvw_d=${1}_data
    local __fvw_c=${FV_DRAW_PAL:0:1}
    fv.video.fillRect "$FV_DRAW_X" "$FV_DRAW_Y" "${__fvw_d[SizeX]:-0}" "${__fvw_d[SizeY]:-0}" "${__fvw_c:-$__FV_VW_ERRSYM}" ' ' || :
}

# TGroup.Draw [NOCLIP] — FV DrawSubViews(First, nil): the visible subviews
# back to front, each painted clipped to the current paint rectangle,
# skipping one whose part in it a covering front sibling holds entirely;
# after a subview with sfShadow its shadow. NOCLIP 1 (from fv.views._paint):
# leave the fv.video clip to the caller; else put the group's back when a
# subview changed it (a Draw override of yours may write after `inherited`)
fv.views._groupDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fvw_l=${1}_views
    local __fvw_n=${#__fvw_l[@]} __fvw_i __fvw_j __fvw_k __fvw_q __fvw_t=0 __fvw_cv __fvw_tl
    local __fvw_p1=$__FV_VW_P1 __fvw_p2=$__FV_VW_P2 __fvw_p3=$__FV_VW_P3 __fvw_p4=$__FV_VW_P4 __fvw_g=$__FV_VW_INGRP
    local __fvw_1 __fvw_2 __fvw_3 __fvw_4
    __FV_VW_INGRP=1
    for (( __fvw_i = 0; __fvw_i < __fvw_n; __fvw_i++ )); do
        __fvw_k=${__fvw_l[__fvw_i]}
        local -n __fvw_kd=${__fvw_k}_data
        if (( ! (${__fvw_kd[State]:-0} & FV_SF_VISIBLE) )); then continue; fi
        __fvw_1=${__FV_VW_C1[$__fvw_k]} __fvw_2=${__FV_VW_C2[$__fvw_k]} __fvw_3=${__FV_VW_C3[$__fvw_k]} __fvw_4=${__FV_VW_C4[$__fvw_k]}
        if (( __fvw_p1 > __fvw_1 )); then __fvw_1=$__fvw_p1; fi
        if (( __fvw_p2 > __fvw_2 )); then __fvw_2=$__fvw_p2; fi
        if (( __fvw_p3 < __fvw_3 )); then __fvw_3=$__fvw_p3; fi
        if (( __fvw_p4 < __fvw_4 )); then __fvw_4=$__fvw_p4; fi
        if (( __fvw_1 < __fvw_3 && __fvw_2 < __fvw_4 )); then
            __fvw_cv=0 __fvw_tl=0
            for (( __fvw_j = __fvw_i + 1; __fvw_j < __fvw_n; __fvw_j++ )); do
                __fvw_q=${__fvw_l[__fvw_j]}
                if (( __FV_VW_C1[$__fvw_q] > __fvw_1 || __FV_VW_C2[$__fvw_q] > __fvw_2 )); then continue; fi
                if (( __FV_VW_C3[$__fvw_q] < __fvw_3 || __FV_VW_C4[$__fvw_q] < __fvw_4 )); then
                    # (it holds the part's top-left cell: several views together may cover the part)
                    if (( __FV_VW_C3[$__fvw_q] > __fvw_1 && __FV_VW_C4[$__fvw_q] > __fvw_2 )); then __fvw_tl=1; fi
                    continue
                fi
                local -n __fvw_qd=${__fvw_q}_data
                if (( ! (${__fvw_qd[State]:-0} & FV_SF_VISIBLE) )); then continue; fi
                if fv.views._covers "$__fvw_q"; then __fvw_cv=1; break; fi
            done
            # (D21: no single view in front covers it: maybe several together,
            # when one of them holds the part's top-left cell)
            if (( ! __fvw_cv && __fvw_tl )) && fv.views._ucover "$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4"; then __fvw_cv=1; fi
            if (( ! __fvw_cv )); then fv.views._paint "$__fvw_k" "$__fvw_p1" "$__fvw_p2" "$__fvw_p3" "$__fvw_p4"; __fvw_t=1; fi
        fi
        if (( ${__fvw_kd[State]:-0} & FV_SF_SHADOW )) && { (( __fvw_i + 1 == __fvw_n )) || ! fv.views._shcover; }; then
            if fv.views._shade "$__fvw_k" "$__fvw_p1" "$__fvw_p2" "$__fvw_p3" "$__fvw_p4"; then __fvw_t=1; fi
        fi
    done
    __FV_VW_INGRP=$__fvw_g
    if (( __fvw_t )) && [[ ${2-} != 1 ]]; then fv.video._clipf "$__fvw_p1" "$__fvw_p2" "$__fvw_p3" "$__fvw_p4"; fi
    return 0
}

# fv.views._ucover X1 Y1 X2 Y2 — _groupDraw's union test (its locals:
# __fvw_l the subviews, __fvw_n their count, __fvw_i the subview drawn): rc 0
# when the visible COVERING subviews in front of it hold the rectangle
# together (each takes its clip out of what is left; FV's own writes are
# clipped by the views in front the same way, so nothing visible changes)
fv.views._ucover() {
    local -a __fvw_ur=("$1" "$2" "$3" "$4") __fvw_un
    local __fvw_j __fvw_q __fvw_e1 __fvw_e2 __fvw_e3 __fvw_e4 __fvw_x __fvw_a1 __fvw_a2 __fvw_a3 __fvw_a4 __fvw_tb __fvw_bb
    for (( __fvw_j = __fvw_i + 1; __fvw_j < __fvw_n; __fvw_j++ )); do
        __fvw_q=${__fvw_l[__fvw_j]}
        __fvw_e1=${__FV_VW_C1[$__fvw_q]} __fvw_e2=${__FV_VW_C2[$__fvw_q]} __fvw_e3=${__FV_VW_C3[$__fvw_q]} __fvw_e4=${__FV_VW_C4[$__fvw_q]}
        __fvw_un=()
        for (( __fvw_x = 0; __fvw_x < ${#__fvw_ur[@]}; __fvw_x += 4 )); do
            __fvw_a1=${__fvw_ur[__fvw_x]} __fvw_a2=${__fvw_ur[__fvw_x+1]} __fvw_a3=${__fvw_ur[__fvw_x+2]} __fvw_a4=${__fvw_ur[__fvw_x+3]}
            if (( __fvw_a1 >= __fvw_e3 || __fvw_e1 >= __fvw_a3 || __fvw_a2 >= __fvw_e4 || __fvw_e2 >= __fvw_a4 )); then
                __fvw_un+=("$__fvw_a1" "$__fvw_a2" "$__fvw_a3" "$__fvw_a4"); continue
            fi
            # (the first piece this view meets: is it a visible covering view at all)
            if [[ -z ${__fvw_tb-} ]]; then
                local -n __fvw_uq=${__fvw_q}_data
                if (( ! (${__fvw_uq[State]:-0} & FV_SF_VISIBLE) )) || ! fv.views._covers "$__fvw_q"; then __fvw_tb=n; else __fvw_tb=y; fi
            fi
            if [ "$__fvw_tb" = n ]; then __fvw_un+=("$__fvw_a1" "$__fvw_a2" "$__fvw_a3" "$__fvw_a4"); continue; fi
            __fvw_bb=$__fvw_a4
            if (( __fvw_a2 < __fvw_e2 )); then __fvw_un+=("$__fvw_a1" "$__fvw_a2" "$__fvw_a3" "$__fvw_e2"); __fvw_a2=$__fvw_e2; fi
            if (( __fvw_e4 < __fvw_bb )); then __fvw_un+=("$__fvw_a1" "$__fvw_e4" "$__fvw_a3" "$__fvw_bb"); __fvw_bb=$__fvw_e4; fi
            if (( __fvw_a1 < __fvw_e1 )); then __fvw_un+=("$__fvw_a1" "$__fvw_a2" "$__fvw_e1" "$__fvw_bb"); fi
            if (( __fvw_e3 < __fvw_a3 )); then __fvw_un+=("$__fvw_e3" "$__fvw_a2" "$__fvw_a3" "$__fvw_bb"); fi
        done
        __fvw_tb=''
        __fvw_ur=("${__fvw_un[@]}")
        if (( ! ${#__fvw_ur[@]} )); then return 0; fi
    done
    return 1
}
# fv.views._shcover — _groupDraw's shadow test (its locals; the subview
# __fvw_k with sfShadow, the paint rectangle __fvw_p1..p4): rc 0 when both
# shadow strips, cut to the paint rectangle, are held by covering subviews in
# front (fv.views._ucover): the shade would be painted over at once. Not
# when a strip's first or last column cuts a wide character of the views
# behind (a continuation cell there, stage 3a-2): the shade marks that
# character's other half too, outside the strip (fv.video's _shadew), which
# stays visible as the half a view in front blanks — skipped, a partial
# repaint whose rectangle holds the strip's part covered would differ from
# a full repaint that shades it (fv.views._shwide)
fv.views._shcover() {
    local -n __fvw_sk=${__fvw_k}_data
    local __fvw_x=${__FV_VW_AX[$__fvw_k]} __fvw_y=${__FV_VW_AY[$__fvw_k]} __fvw_w=${__fvw_sk[SizeX]:-0} __fvw_h=${__fvw_sk[SizeY]:-0}
    local __fvw_s1 __fvw_s2 __fvw_s3 __fvw_s4 __fvw_z __fvw_j __fvw_q
    for __fvw_z in 0 1; do
        if (( __fvw_z )); then __fvw_s1=$(( __fvw_x + 2 )) __fvw_s2=$(( __fvw_y + __fvw_h )) __fvw_s3=$(( __fvw_x + __fvw_w )) __fvw_s4=$(( __fvw_y + __fvw_h + 1 ))
        else __fvw_s1=$(( __fvw_x + __fvw_w )) __fvw_s2=$(( __fvw_y + 1 )) __fvw_s3=$(( __fvw_x + __fvw_w + 2 )) __fvw_s4=$(( __fvw_y + __fvw_h + 1 )); fi
        if (( __fvw_s1 < __fvw_p1 )); then __fvw_s1=$__fvw_p1; fi
        if (( __fvw_s2 < __fvw_p2 )); then __fvw_s2=$__fvw_p2; fi
        if (( __fvw_s3 > __fvw_p3 )); then __fvw_s3=$__fvw_p3; fi
        if (( __fvw_s4 > __fvw_p4 )); then __fvw_s4=$__fvw_p4; fi
        if (( __fvw_s1 >= __fvw_s3 || __fvw_s2 >= __fvw_s4 )); then continue; fi
        # (a view in front must hold the strip's top-left cell: most shadows
        # end here, before the subtraction)
        for (( __fvw_j = __fvw_i + 1; __fvw_j < __fvw_n; __fvw_j++ )); do
            __fvw_q=${__fvw_l[__fvw_j]}
            if (( __FV_VW_C1[$__fvw_q] <= __fvw_s1 && __FV_VW_C2[$__fvw_q] <= __fvw_s2 && __FV_VW_C3[$__fvw_q] > __fvw_s1 && __FV_VW_C4[$__fvw_q] > __fvw_s2 )); then break; fi
        done
        if (( __fvw_j == __fvw_n )); then return 1; fi
        fv.views._ucover "$__fvw_s1" "$__fvw_s2" "$__fvw_s3" "$__fvw_s4" || return 1
    done
    # (covered: rows with wide cells looked at, only then)
    if [[ ${__FV_VS_WIDE[*]-} == *[13]* ]] && fv.views._shwide; then return 1; fi
    return 0
}
# fv.views._shwide — _shcover's wide test (its locals): rc 0 when a row of a
# shadow strip cut to the paint rectangle holds wide cells and a
# continuation cell at the strip's first or last column (where fv.video's
# _shadew widens the shade); a caller whose locale is not UTF-8 (the read
# indexes characters): rc 0 for any such row with wide cells
fv.views._shwide() {
    local __fvw_z __fvw_t
    for __fvw_z in 0 1; do
        if (( __fvw_z )); then __fvw_s1=$(( __fvw_x + 2 )) __fvw_s2=$(( __fvw_y + __fvw_h )) __fvw_s3=$(( __fvw_x + __fvw_w )) __fvw_s4=$(( __fvw_y + __fvw_h + 1 ))
        else __fvw_s1=$(( __fvw_x + __fvw_w )) __fvw_s2=$(( __fvw_y + 1 )) __fvw_s3=$(( __fvw_x + __fvw_w + 2 )) __fvw_s4=$(( __fvw_y + __fvw_h + 1 )); fi
        if (( __fvw_s1 < __fvw_p1 )); then __fvw_s1=$__fvw_p1; fi
        if (( __fvw_s2 < __fvw_p2 )); then __fvw_s2=$__fvw_p2; fi
        if (( __fvw_s3 > __fvw_p3 )); then __fvw_s3=$__fvw_p3; fi
        if (( __fvw_s4 > __fvw_p4 )); then __fvw_s4=$__fvw_p4; fi
        for (( ; __fvw_s2 < __fvw_s4 && __fvw_s1 < __fvw_s3; __fvw_s2++ )); do
            if (( ! (${__FV_VS_WIDE[__fvw_s2]:-0} & 1) )); then continue; fi
            if (( ${#__FV_VS_PB} != 2 )); then return 0; fi
            __fvw_t=${__FV_VS_CH[__fvw_s2]}
            if [[ ${__fvw_t:__fvw_s1:1} == "$__FV_VS_CONT" || ${__fvw_t:__fvw_s3:1} == "$__FV_VS_CONT" ]]; then return 0; fi
        done
    done
    return 1
}

# TView.GetPalette (func) — FV: nil, '' (the view maps as its owner does)
fv.views._viewGetPalette() { RESULT=''; }
# TFrame.GetPalette (func) — FV CFrame: passive frame, passive title, active
# frame, active title, icons
fv.views._frameGetPalette() { RESULT='1 1 2 2 3'; }

# ---- TFrame (design §1.5; FV TFrame.Draw, FrameLine) -----------------------------
fv.views._frameCreate() {   # F
    local -n __fvw_d=${1}_data
    __fvw_d[GrowMode]=$(( FV_GF_GROWHIX | FV_GF_GROWHIY ))
    __fvw_d[EventMask]=$(( ${__fvw_d[EventMask]:-0} | FV_EM_BROADCAST ))
    __fvw_d[FrameMode]=0
    __FV_VW_FRM[$1]=1
}

# fv.views._frameTitle O L — the caller's __fvw_ti = the owner's title as
# asked for at most L characters (FV: GetTitle(L), a func of TWindow from
# stage 2c-3, through the elision when O's class has one; else the owner's
# Title field). Not cut here: fv.views._titleFit cuts it on a cache miss
fv.views._frameTitle() {
    local __fvw_c=${1}_class __fvw_r=${RESULT-}
    __fvw_c="${!__fvw_c-}_class_method_owner[GetTitle]"
    if [ "${__FV_VW_IMPL[${!__fvw_c-}.GetTitle]-}" = fv.views._windowGetTitle ]; then
        # (TWindow's GetTitle, inline: no RESULT to save and restore)
        local -n __fvw_od=${1}_data
        __fvw_ti=${__fvw_od[Title]-}
        if [[ -n $2 && $2 != *[!0123456789]* && ${#2} -le 9 ]] && (( ${#__fvw_ti} > 10#$2 )); then __fvw_ti=${__fvw_ti:0:10#$2}; fi
    elif [[ -n ${!__fvw_c-} ]]; then
        RESULT=''
        fv.views._virt "$1" GetTitle "$2" || RESULT=''
        __fvw_ti=${RESULT-}
        RESULT=$__fvw_r
    else
        local -n __fvw_od=${1}_data
        __fvw_ti=${__fvw_od[Title]-}
    fi
}

# fv.views._titleFit L — the caller's __fvw_ti cut to at most L characters
# (TWindow.GetTitle's Copy) and then to at most L cells; __fvw_tw = its width.
# Runs through fv.video._g (fv.video's locale guard): a caller in a non-UTF-8
# locale would otherwise cut a UTF-8 title by bytes
fv.views._titleFit() {
    if (( $1 <= 0 )); then __fvw_ti='' __fvw_tw=0; return 0; fi
    if (( ${#__fvw_ti} > $1 )); then __fvw_ti=${__fvw_ti:0:$1}; fi
    fv.video.strWidth "$__fvw_ti" || RESULT=${#__fvw_ti}
    __fvw_tw=$RESULT
    while (( __fvw_tw > $1 )) && [[ -n $__fvw_ti ]]; do
        __fvw_ti=${__fvw_ti%?}
        fv.video.strWidth "$__fvw_ti" || RESULT=${#__fvw_ti}
        __fvw_tw=$RESULT
    done
}

# fv.views._frameRows F — the frame's row strings for its state, size,
# owner fields and palette, cached per frame and state slot (active x
# dragging; the caller's __fvw_fc = "F.SLOT" names it, __FV_VW_FK[F.SLOT]
# the key of what it holds): FT/FTA top, FM/FMA body, FB/FBA bottom (text /
# symbols), FS/FSA the side column.
# FV TFrame.Draw: by state (sfDragging: single line, everything in colour 5;
# not sfActive: single, frame 1, title 2; active: double, frame 3, icons 5,
# title 4); the number (1..9) at W-3 (W-7 with wfZoom); the title centred,
# a blank either side, in the title colour; while active `[■]` at 2
# (wfClose; `☼` while FrameMode has fmCloseClicked), `[↑]` at W-5 (wfZoom;
# `↕` when the owner is at its SizeLimits maximum, `☼` with fmZoomClicked),
# the grow corner `─┘` at W-2 in colour 5 (wfGrow). FV's junctions with
# ofFramed subviews are not drawn (deviation). The title is cut so that it
# never reaches an icon (FV caps it at W-10 only after asking for L).
fv.views._frameRows() {
    local -n __fvw_d=${1}_data
    local __fvw_o=${__fvw_d[Owner]-} __fvw_w=${__fvw_d[SizeX]:-0} __fvw_st=${__fvw_d[State]:-0} __fvw_fm=${__fvw_d[FrameMode]:-0}
    local __fvw_fl=0 __fvw_nm=0 __fvw_ti='' __fvw_z=0 __fvw_lo __fvw_hi __fvw_tc __fvw_f __fvw_a __fvw_L __fvw_key
    if [[ -z ${__FV_VW_PAL[$1]+x} ]]; then fv.views._pal "$1"; fi
    local __fvw_p=${__FV_VW_PAL[$1]}
    if (( __fvw_st & FV_SF_DRAGGING )); then __fvw_lo=5 __fvw_hi=5 __fvw_tc=5 __fvw_f=0
    elif (( ! (__fvw_st & FV_SF_ACTIVE) )); then __fvw_lo=1 __fvw_hi=1 __fvw_tc=2 __fvw_f=0
    else __fvw_lo=3 __fvw_hi=5 __fvw_tc=4 __fvw_f=9; fi
    __fvw_a=$(( (__fvw_st & FV_SF_ACTIVE) ? 1 : 0 ))
    if [[ -n $__fvw_o ]]; then
        local -n __fvw_od=${__fvw_o}_data
        __fvw_fl=${__fvw_od[Flags]:-0} __fvw_nm=${__fvw_od[Number]:-0}
        if [[ $__fvw_fl == *[!0123456789]* || ${#__fvw_fl} -gt 9 ]]; then __fvw_fl=0; else __fvw_fl=$(( 10#$__fvw_fl )); fi
        if ! [[ $__fvw_nm == [123456789] ]]; then __fvw_nm=0; fi
    fi
    __fvw_L=$(( __fvw_w - 10 ))
    if (( __fvw_fl & (FV_WF_CLOSE | FV_WF_ZOOM) )); then __fvw_L=$(( __fvw_L - 6 )); fi
    if (( __fvw_nm )); then __fvw_L=$(( __fvw_L - 4 )); fi
    if [[ -n $__fvw_o ]]; then fv.views._frameTitle "$__fvw_o" "$__fvw_L"; fi
    if (( __fvw_a && (__fvw_fl & FV_WF_ZOOM) )) && [[ -n $__fvw_o ]]; then fv.views._frameZoom; fi
    # one cache slot per state (active x dragging), so a focus change back and
    # forth finds both looks built: the caller's __fvw_fc = "F.SLOT"
    __fvw_fc="$1.$(( (__fvw_st & FV_SF_DRAGGING ? 2 : 0) + __fvw_a ))"
    __fvw_key="$__fvw_f.$__fvw_lo$__fvw_hi$__fvw_tc.$__fvw_a.$__fvw_w.$__fvw_fl.$__fvw_nm.$__fvw_fm.$__fvw_z.${FV_VIDEO_ASCII:-0}.$__fvw_p|$__fvw_ti"
    if [ "${__FV_VW_FK[$__fvw_fc]-}" = "$__fvw_key" ]; then return 0; fi
    fv.views._frameBuild
}
# fv.views._frameZoom — _frameRows' zoom icon state (its locals: __fvw_o the
# owner, __fvw_od its data): __fvw_z=1 when the owner is at its SizeLimits
# maximum (TView's SizeLimits inline: the owner's owner's size)
fv.views._frameZoom() {
    local __fvw_k="${__fvw_o}_class"
    __fvw_k="${!__fvw_k-}_class_method_owner[SizeLimits]"
    __fvw_k=${__FV_VW_IMPL[${!__fvw_k-}.SizeLimits]-}
    if [ "$__fvw_k" = fv.views._viewSizeLimits ] || [ "$__fvw_k" = fv.views._windowSizeLimits ]; then
        # (TView's / TWindow's SizeLimits, inline: the maximum is the owner's
        # owner's size)
        __fvw_k=${__fvw_od[Owner]-}
        if [[ -n $__fvw_k ]]; then
            local -n __fvw_oo=${__fvw_k}_data
            if (( ${__fvw_od[SizeX]:-0} == ${__fvw_oo[SizeX]:-0} && ${__fvw_od[SizeY]:-0} == ${__fvw_oo[SizeY]:-0} )); then __fvw_z=1; fi
        elif (( ${__fvw_od[SizeX]:-0} == __FV_VW_HIGH && ${__fvw_od[SizeY]:-0} == __FV_VW_HIGH )); then __fvw_z=1; fi
    else
        local __fvw_m1=$FV_MIN_X __fvw_m2=$FV_MIN_Y __fvw_m3=$FV_MAX_X __fvw_m4=$FV_MAX_Y
        fv.views._virt "$__fvw_o" SizeLimits || :
        if (( ${__fvw_od[SizeX]:-0} == FV_MAX_X && ${__fvw_od[SizeY]:-0} == FV_MAX_Y )); then __fvw_z=1; fi
        FV_MIN_X=$__fvw_m1 FV_MIN_Y=$__fvw_m2 FV_MAX_X=$__fvw_m3 FV_MAX_Y=$__fvw_m4
    fi
}
# fv.views._frameBuild — _frameRows' cache miss (its locals): the rows built
# into the slot __fvw_fc under the key __fvw_key. Apart because bash copies a
# function's whole body on every call (stage 2c-p): the cache hit stays short
fv.views._frameBuild() {
    local __fvw_cl=${__fvw_p:__fvw_lo-1:1} __fvw_ch=${__fvw_p:__fvw_hi-1:1} __fvw_ct=${__fvw_p:__fvw_tc-1:1}
    __fvw_cl=${__fvw_cl:-$__FV_VW_ERRSYM} __fvw_ch=${__fvw_ch:-$__FV_VW_ERRSYM} __fvw_ct=${__fvw_ct:-$__FV_VW_ERRSYM}
    local __fvw_tl __fvw_hz __fvw_tr __fvw_vl __fvw_bl __fvw_br __fvw_s __fvw_r __fvw_i __fvw_n
    if (( __fvw_f )); then __fvw_tl='╔' __fvw_hz='═' __fvw_tr='╗' __fvw_vl='║' __fvw_bl='╚' __fvw_br='╝'
    else __fvw_tl='┌' __fvw_hz='─' __fvw_tr='┐' __fvw_vl='│' __fvw_bl='└' __fvw_br='┘'; fi
    if (( __fvw_w < 1 )); then
        __FV_VW_FT[$__fvw_fc]='' __FV_VW_FTA[$__fvw_fc]='' __FV_VW_FM[$__fvw_fc]='' __FV_VW_FMA[$__fvw_fc]='' __FV_VW_FB[$__fvw_fc]='' __FV_VW_FBA[$__fvw_fc]=''
        __FV_VW_FS[$__fvw_fc]=$__fvw_vl __FV_VW_FSA[$__fvw_fc]=$__fvw_cl __FV_VW_FK[$__fvw_fc]=$__fvw_key
        return 0
    fi
    __fvw_n=$(( __fvw_w > 2 ? __fvw_w - 2 : 0 ))
    # the cells as array elements (box characters are several bytes: no
    # substring offsets on them, whatever the caller's locale)
    local -a __fvw_tc_=() __fvw_bc=()
    printf -v __fvw_r '%*s' "$__fvw_n" ''
    __fvw_s=${__fvw_r// /"$__fvw_hz "}
    local IFS=' '
    # (unquoted on purpose: box characters and blanks only, no glob character; split on the blanks)
    __fvw_tc_=($__fvw_tl $__fvw_s $__fvw_tr) __fvw_bc=($__fvw_bl $__fvw_s $__fvw_br)
    if (( __fvw_w == 1 )); then __fvw_tc_=("$__fvw_tr") __fvw_bc=("$__fvw_br"); fi
    printf -v __fvw_s '%*s' "$__fvw_w" ''
    local __fvw_ta=${__fvw_s// /$__fvw_cl} __fvw_ba=${__fvw_s// /$__fvw_cl}
    # the number (its cell keeps the frame colour)
    if (( __fvw_nm )); then
        if (( __fvw_fl & FV_WF_ZOOM )); then __fvw_i=$(( __fvw_w - 7 )); else __fvw_i=$(( __fvw_w - 3 )); fi
        if (( __fvw_i >= 0 )); then __fvw_tc_[__fvw_i]=$__fvw_nm; fi
    fi
    # the title block: blank, title, blank in the title colour
    if [[ -n $__fvw_ti ]]; then
        # (cut to L, its width in cells as a write stores it: wide characters, marks)
        local __fvw_tw=0
        fv.video._g fv.views._titleFit "$__fvw_L" || :
        if (( __fvw_tw > 0 )); then
            __fvw_i=$(( (__fvw_w - __fvw_tw) >> 1 ))
            __fvw_tc_[__fvw_i-1]=' ' __fvw_tc_[__fvw_i]=$__fvw_ti __fvw_tc_[__fvw_i+__fvw_tw]=' '
            for (( __fvw_n = __fvw_i + 1; __fvw_n < __fvw_i + __fvw_tw; __fvw_n++ )); do __fvw_tc_[__fvw_n]=''; done
            printf -v __fvw_s '%*s' "$(( __fvw_tw + 2 ))" ''
            __fvw_ta=${__fvw_ta:0:__fvw_i-1}${__fvw_s// /$__fvw_ct}${__fvw_ta:__fvw_i+__fvw_tw+1}
        fi
    fi
    # the icons, while active
    if (( __fvw_a )); then
        if (( (__fvw_fl & FV_WF_CLOSE) && __fvw_w > 4 )); then
            __fvw_tc_[2]='[' __fvw_tc_[4]=']'
            if (( __fvw_fm & FV_FM_CLOSECLICKED )); then __fvw_tc_[3]='☼'; else __fvw_tc_[3]='■'; fi
            __fvw_ta=${__fvw_ta:0:2}$__fvw_cl$__fvw_ch$__fvw_cl${__fvw_ta:5}
        fi
        if (( (__fvw_fl & FV_WF_ZOOM) && __fvw_w >= 5 )); then
            __fvw_i=$(( __fvw_w - 5 ))
            __fvw_tc_[__fvw_i]='[' __fvw_tc_[__fvw_i+1]='↑' __fvw_tc_[__fvw_i+2]=']'
            if (( __fvw_fm & FV_FM_ZOOMCLICKED )); then __fvw_tc_[__fvw_i+1]='☼'; elif (( __fvw_z )); then __fvw_tc_[__fvw_i+1]='↕'; fi
            __fvw_ta=${__fvw_ta:0:__fvw_i}$__fvw_cl$__fvw_ch$__fvw_cl${__fvw_ta:__fvw_i+3}
        fi
        if (( (__fvw_fl & FV_WF_GROW) && __fvw_w >= 2 )); then
            __fvw_bc[__fvw_w-2]='─' __fvw_bc[__fvw_w-1]='┘'
            __fvw_ba=${__fvw_ba:0:__fvw_w-2}$__fvw_ch$__fvw_ch
        fi
    fi
    IFS=''
    printf -v "__FV_VW_FT[$__fvw_fc]" '%s' "${__fvw_tc_[@]}"
    printf -v "__FV_VW_FB[$__fvw_fc]" '%s' "${__fvw_bc[@]}"
    printf -v __fvw_s '%*s' "$(( __fvw_w > 2 ? __fvw_w - 2 : 0 ))" ''
    if (( __fvw_w == 1 )); then __FV_VW_FM[$__fvw_fc]=$__fvw_vl; else __FV_VW_FM[$__fvw_fc]=$__fvw_vl$__fvw_s$__fvw_vl; fi
    __FV_VW_FTA[$__fvw_fc]=$__fvw_ta __FV_VW_FBA[$__fvw_fc]=$__fvw_ba __FV_VW_FMA[$__fvw_fc]=${__fvw_ba//?/$__fvw_cl}
    __FV_VW_FS[$__fvw_fc]=$__fvw_vl __FV_VW_FSA[$__fvw_fc]=$__fvw_cl __FV_VW_FK[$__fvw_fc]=$__fvw_key
}

# TFrame.Draw — FV: the top row, the body row on the H-2 rows between, the
# bottom row: three writes (fv.video.writeBuf, the body with its repeat count)
fv.views._frameDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fvw_d=${1}_data
    local __fvw_h=${__fvw_d[SizeY]:-0} __fvw_fc
    if (( ${__fvw_d[SizeX]:-0} < 1 )); then return 0; fi
    fv.views._frameRows "$1"
    fv.video._wbf "$FV_DRAW_X" "$FV_DRAW_Y" "${__FV_VW_FT[$__fvw_fc]}" "${__FV_VW_FTA[$__fvw_fc]}" || :
    if (( __fvw_h > 2 )); then
        fv.video._wbf "$FV_DRAW_X" "$(( FV_DRAW_Y + 1 ))" "${__FV_VW_FM[$__fvw_fc]}" "${__FV_VW_FMA[$__fvw_fc]}" "$(( __fvw_h - 2 ))" || :
    fi
    fv.video._wbf "$FV_DRAW_X" "$(( FV_DRAW_Y + __fvw_h - 1 ))" "${__FV_VW_FB[$__fvw_fc]}" "${__FV_VW_FBA[$__fvw_fc]}" || :
}

# fv.views._frameBorder F — the BORDER-ONLY redraw (stage 2c-3 calls it when
# sfActive or sfDragging changes; design §1.5): the top and bottom rows and
# the two side columns, then the views in front over what was written
# (scroll bars on the ring, shadows), flush. The interior is not touched.
# The parts of the ring that a covering view in front of the frame (or of an
# owner) holds are left out first (fv.views._uncover), so a window in front
# is neither overwritten nor painted again: 4 writes for an uncovered ring,
# one more per extra piece of a ring cut by a window in front. A frame whose
# class overrides Draw is drawn whole (drawView: its Draw runs).
fv.views._frameBorder() {
    local __fvw_o=${1}_class __fvw_r=${RESULT-}
    __fvw_o="${!__fvw_o-}_class_method_owner[Draw]"
    if ! [ "${__FV_VW_IMPL[${!__fvw_o-}.Draw]-}" = fv.views._frameDraw ]; then fv.views._drawView "$1"; RESULT=$__fvw_r; return 0; fi
    fv.views._drawable "$1" || return 0
    local -n __fvw_d=${1}_data
    local __fvw_x=${__FV_VW_AX[$1]} __fvw_y=${__FV_VW_AY[$1]} __fvw_w=${__fvw_d[SizeX]:-0} __fvw_h=${__fvw_d[SizeY]:-0}
    if (( __fvw_w < 1 || __fvw_h < 1 )); then return 0; fi
    fv.views._frameRing "$1"
    RESULT=$__fvw_r
}
# fv.views._frameRing F — _frameBorder's work (its locals __fvw_x __fvw_y
# __fvw_w __fvw_h __fvw_r): the ring's pieces, what covers them, the writes,
# the views in front, the flush. Apart because bash copies a function's body
# on every call: a frame that is not drawn (hidden, the view drawn whole
# right after) pays only for the checks
fv.views._frameRing() {
    local __fvw_bg __fvw_b1 __fvw_b2 __fvw_b3 __fvw_b4 __fvw_j __fvw_1 __fvw_2 __fvw_3 __fvw_4 __fvw_c=0
    # the ring as pieces (X1 Y1 X2 Y2) with a tag: t top, b bottom, s side
    local -a __fvw_rs=() __fvw_tg=() __fvw_q=(
        "$__fvw_x" "$__fvw_y" "$(( __fvw_x + __fvw_w ))" "$(( __fvw_y + 1 ))"
        "$__fvw_x" "$(( __fvw_y + __fvw_h - 1 ))" "$(( __fvw_x + __fvw_w ))" "$(( __fvw_y + __fvw_h ))")
    local -a __fvw_qt=(t b)
    if (( __fvw_h > 2 )); then
        __fvw_q+=("$__fvw_x" "$(( __fvw_y + 1 ))" "$(( __fvw_x + 1 ))" "$(( __fvw_y + __fvw_h - 1 ))")
        __fvw_qt+=(s)
        if (( __fvw_w > 1 )); then
            __fvw_q+=("$(( __fvw_x + __fvw_w - 1 ))" "$(( __fvw_y + 1 ))" "$(( __fvw_x + __fvw_w ))" "$(( __fvw_y + __fvw_h - 1 ))")
            __fvw_qt+=(s)
        fi
    fi
    # each clipped to the frame's clip (the whole ring inside it: as built)
    if (( __fvw_x >= __FV_VW_C1[$1] && __fvw_y >= __FV_VW_C2[$1] && __fvw_x + __fvw_w <= __FV_VW_C3[$1] && __fvw_y + __fvw_h <= __FV_VW_C4[$1] )); then
        __fvw_rs=("${__fvw_q[@]}") __fvw_tg=("${__fvw_qt[@]}")
    else
        for (( __fvw_j = 0; __fvw_j < ${#__fvw_q[@]}; __fvw_j += 4 )); do
            __fvw_1=${__fvw_q[__fvw_j]} __fvw_2=${__fvw_q[__fvw_j+1]} __fvw_3=${__fvw_q[__fvw_j+2]} __fvw_4=${__fvw_q[__fvw_j+3]}
            if (( __fvw_1 < __FV_VW_C1[$1] )); then __fvw_1=${__FV_VW_C1[$1]}; fi
            if (( __fvw_2 < __FV_VW_C2[$1] )); then __fvw_2=${__FV_VW_C2[$1]}; fi
            if (( __fvw_3 > __FV_VW_C3[$1] )); then __fvw_3=${__FV_VW_C3[$1]}; fi
            if (( __fvw_4 > __FV_VW_C4[$1] )); then __fvw_4=${__FV_VW_C4[$1]}; fi
            if (( __fvw_1 < __fvw_3 && __fvw_2 < __fvw_4 )); then
                __fvw_rs+=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4") __fvw_tg+=("${__fvw_qt[__fvw_j/4]}")
            fi
        done
    fi
    fv.views._uncover "$1"
    if (( ! ${#__fvw_rs[@]} )); then RESULT=$__fvw_r; return 0; fi
    # (rows with wide cells: the edge test before anything is written; when it
    # banded or widened pieces, the views in front go over those, else over
    # the ring pieces)
    local -a __fvw_ro=() __fvw_rb=()
    if (( ${#__FV_VW_WROW[@]} )); then
        __fvw_ro=("${__fvw_rs[@]}")
        fv.views._bands
        if (( __FV_VW_BANDED )); then __fvw_rb=("${__fvw_rs[@]}"); fi
        __fvw_rs=("${__fvw_ro[@]}")
    fi
    fv.views._begin
    local __fvw_fc __fvw_p1='' __fvw_p2 __fvw_p3
    fv.views._frameRows "$1"
    # the side pieces under the frame's clip (two pieces on the same rows, the
    # usual pair of sides: one fv.video.fillColumns), then each row piece
    # under its own clip
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        if ! [ "${__fvw_tg[__fvw_j/4]}" = s ]; then continue; fi
        if (( ! __fvw_c )); then
            fv.video._clipf "${__FV_VW_C1[$1]}" "${__FV_VW_C2[$1]}" "${__FV_VW_C3[$1]}" "${__FV_VW_C4[$1]}"
            __fvw_c=1
        fi
        if [[ -n $__fvw_p1 ]] && (( __fvw_rs[__fvw_j+1] == __fvw_p2 && __fvw_rs[__fvw_j+3] == __fvw_p3 )); then
            fv.video._fcf "$__fvw_p2" "$(( __fvw_p3 - __fvw_p2 ))" "${__FV_VW_FSA[$__fvw_fc]}" "${__FV_VW_FS[$__fvw_fc]}" "$__fvw_p1" "${__fvw_rs[__fvw_j]}" || :
            __fvw_p1=''
            continue
        fi
        if [[ -n $__fvw_p1 ]]; then
            fv.video._fcf "$__fvw_p2" "$(( __fvw_p3 - __fvw_p2 ))" "${__FV_VW_FSA[$__fvw_fc]}" "${__FV_VW_FS[$__fvw_fc]}" "$__fvw_p1" || :
        fi
        __fvw_p1=${__fvw_rs[__fvw_j]} __fvw_p2=${__fvw_rs[__fvw_j+1]} __fvw_p3=${__fvw_rs[__fvw_j+3]}
    done
    if [[ -n $__fvw_p1 ]]; then
        fv.video._fcf "$__fvw_p2" "$(( __fvw_p3 - __fvw_p2 ))" "${__FV_VW_FSA[$__fvw_fc]}" "${__FV_VW_FS[$__fvw_fc]}" "$__fvw_p1" || :
    fi
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        if [ "${__fvw_tg[__fvw_j/4]}" = s ]; then continue; fi
        fv.video._clipf "${__fvw_rs[@]:__fvw_j:4}"
        if [ "${__fvw_tg[__fvw_j/4]}" = t ]; then
            fv.video._wbf "$__fvw_x" "$__fvw_y" "${__FV_VW_FT[$__fvw_fc]}" "${__FV_VW_FTA[$__fvw_fc]}" || :
        else
            fv.video._wbf "$__fvw_x" "$(( __fvw_y + __fvw_h - 1 ))" "${__FV_VW_FB[$__fvw_fc]}" "${__FV_VW_FBA[$__fvw_fc]}" || :
        fi
    done
    # the views in front over what was written (one pass over all pieces: a
    # non-covering view meeting several pieces is painted once per piece)
    # (rows with wide cells make full-width bands of the pieces: then they
    # are no ring any more)
    if (( ${#__fvw_rb[@]} )); then __fvw_rs=("${__fvw_rb[@]}"); fv.views._over "$1"; else fv.views._over "$1" ring; fi
    if (( ${#__FV_VW_WROW[@]} || ${#__FV_VS_WNEW[@]} )) || [[ ${__FV_VS_WIDE[*]-} == *[123]* ]]; then fv.views._wideMark; fi
    fv.views._end
    fv.views._flush
    RESULT=$__fvw_r
}

# fv.views._uncover V — remove from the caller's pieces (__fvw_rs, one cell
# thick, tags in __fvw_tg) what a COVERING visible view in front of V or of
# one of V's owners holds (its clip): such a view hides them entirely (FV
# relies on z-clipping there). A row piece keeps its parts left and right of
# the view, a column piece those above and below
fv.views._uncover() {
    local __fvw_q __fvw_k __fvw_j __fvw_hit
    local __fvw_1 __fvw_2 __fvw_3 __fvw_4 __fvw_e1 __fvw_e2 __fvw_e3 __fvw_e4 __fvw_t
    # (D21: the views in front of V or of an owner, from the structure cache)
    if [[ -z ${__FV_VW_FRL[$1]+x} ]]; then fv.views._frontList "$1"; fi
    __fvw_q=${__FV_VW_FRL[$1]}
    if [[ -z $__fvw_q ]]; then return 0; fi
    # (the ring's box: V's absolute rect)
    local -n __fvw_bd=${1}_data
    local __fvw_b1=${__FV_VW_AX[$1]} __fvw_b2=${__FV_VW_AY[$1]} __fvw_b3 __fvw_b4
    __fvw_b3=$(( __fvw_b1 + ${__fvw_bd[SizeX]:-0} )) __fvw_b4=$(( __fvw_b2 + ${__fvw_bd[SizeY]:-0} ))
    while [[ -n $__fvw_q ]] && (( ${#__fvw_rs[@]} )); do
        __fvw_k=${__fvw_q%% *} __fvw_q=${__fvw_q#*[ ]}
        __fvw_e1=${__FV_VW_C1[$__fvw_k]} __fvw_e2=${__FV_VW_C2[$__fvw_k]} __fvw_e3=${__FV_VW_C3[$__fvw_k]} __fvw_e4=${__FV_VW_C4[$__fvw_k]}
        # (one test for a view that misses the ring's box or lies inside
        # its interior: the pieces are one cell thick, on V's border)
        if (( __fvw_e1 >= __fvw_b3 || __fvw_b1 >= __fvw_e3 || __fvw_e2 >= __fvw_b4 || __fvw_b2 >= __fvw_e4 )) \
           || (( __fvw_e1 > __fvw_b1 && __fvw_e3 < __fvw_b3 && __fvw_e2 > __fvw_b2 && __fvw_e4 < __fvw_b4 )); then continue; fi
        __fvw_hit=0
        for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
            if (( __fvw_rs[__fvw_j] < __fvw_e3 && __fvw_e1 < __fvw_rs[__fvw_j+2] )); then
                if (( __fvw_rs[__fvw_j+1] < __fvw_e4 && __fvw_e2 < __fvw_rs[__fvw_j+3] )); then __fvw_hit=1; break; fi
            fi
        done
        if (( ! __fvw_hit )); then continue; fi
        local -n __fvw_kd=${__fvw_k}_data
        if (( ! (${__fvw_kd[State]:-0} & FV_SF_VISIBLE) )); then continue; fi
        if ! fv.views._covers "$__fvw_k"; then continue; fi
        fv.views._uncut
    done
    return 0
}
# fv.views._uncut — _uncover's cut (its locals): the pieces __fvw_rs / tags
# __fvw_tg without what the covering view's clip __fvw_e1..e4 holds. Apart
# because bash copies a function's body on every call: most borders are cut
# by nothing
fv.views._uncut() {
    local -a __fvw_nr=() __fvw_nt=()
    for (( __fvw_j = 0; __fvw_j < ${#__fvw_rs[@]}; __fvw_j += 4 )); do
        __fvw_1=${__fvw_rs[__fvw_j]} __fvw_2=${__fvw_rs[__fvw_j+1]} __fvw_3=${__fvw_rs[__fvw_j+2]} __fvw_4=${__fvw_rs[__fvw_j+3]}
        __fvw_t=${__fvw_tg[__fvw_j/4]}
        if (( __fvw_1 >= __fvw_e3 || __fvw_e1 >= __fvw_3 || __fvw_2 >= __fvw_e4 || __fvw_e2 >= __fvw_4 )); then
            __fvw_nr+=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_4") __fvw_nt+=("$__fvw_t")
        elif (( __fvw_4 - __fvw_2 == 1 )); then
            if (( __fvw_1 < __fvw_e1 )); then __fvw_nr+=("$__fvw_1" "$__fvw_2" "$__fvw_e1" "$__fvw_4") __fvw_nt+=("$__fvw_t"); fi
            if (( __fvw_e3 < __fvw_3 )); then __fvw_nr+=("$__fvw_e3" "$__fvw_2" "$__fvw_3" "$__fvw_4") __fvw_nt+=("$__fvw_t"); fi
        else
            if (( __fvw_2 < __fvw_e2 )); then __fvw_nr+=("$__fvw_1" "$__fvw_2" "$__fvw_3" "$__fvw_e2") __fvw_nt+=("$__fvw_t"); fi
            if (( __fvw_e4 < __fvw_4 )); then __fvw_nr+=("$__fvw_1" "$__fvw_e4" "$__fvw_3" "$__fvw_4") __fvw_nt+=("$__fvw_t"); fi
        fi
    done
    __fvw_rs=("${__fvw_nr[@]}") __fvw_tg=("${__fvw_nt[@]}")
}

# ==== events, focus, commands, modal views (P2 stage 2c-3; design §1.8, §2.2) ====
#
# The event is fv.drivers' record, the FV_EV_* globals: FV_EV_WHAT names it
# (evKeyDown, evMouseDown, evCommand, evBroadcast, …), FV_EV_COMMAND is a
# command name, FV_EV_INFO is FV's InfoPtr / InfoInt (a view name or a
# number; '' = nil). A handler marks an event handled with
# fv.views.clearEvent V (FV ClearEvent). The loops that start an event of
# their own (message, execView) save the record and put it back: FV keeps a
# local Event per loop. Phases and commands are names.

# fv.views._evSave / _evRestore — the record (the 14 fields of FV's TEvent,
# then FV_EV_BASE, the base-layout key: P3 3L) into / from the caller's array
# __fvw_es
fv.views._evSave() {
    __fvw_es=("$FV_EV_WHAT" "$FV_EV_KEY" "$FV_EV_CHAR" "$FV_EV_COMMAND" "$FV_EV_ID" "$FV_EV_INFO"
        "$FV_EV_MOUSE_X" "$FV_EV_MOUSE_Y" "$FV_EV_MOUSE_BUTTONS" "$FV_EV_MOUSE_MODS"
        "$FV_EV_MOUSE_DOUBLE" "$FV_EV_MOUSE_TRIPLE" "$FV_EV_WHEEL" "$FV_EV_EOF" "${FV_EV_BASE-}")
}
fv.views._evRestore() {
    FV_EV_WHAT=${__fvw_es[0]} FV_EV_KEY=${__fvw_es[1]} FV_EV_CHAR=${__fvw_es[2]} FV_EV_COMMAND=${__fvw_es[3]}
    FV_EV_ID=${__fvw_es[4]} FV_EV_INFO=${__fvw_es[5]} FV_EV_MOUSE_X=${__fvw_es[6]} FV_EV_MOUSE_Y=${__fvw_es[7]}
    FV_EV_MOUSE_BUTTONS=${__fvw_es[8]} FV_EV_MOUSE_MODS=${__fvw_es[9]} FV_EV_MOUSE_DOUBLE=${__fvw_es[10]}
    FV_EV_MOUSE_TRIPLE=${__fvw_es[11]} FV_EV_WHEEL=${__fvw_es[12]} FV_EV_EOF=${__fvw_es[13]} FV_EV_BASE=${__fvw_es[14]-}
}

# fv.views.clearEvent V — FV ClearEvent: the event is handled (FV_EV_WHAT =
# evNothing) by V (FV_EV_INFO = V: what fv.views.message answers)
fv.views.clearEvent() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    FV_EV_WHAT=evNothing FV_EV_INFO=$1
}

# fv.views.hotKeyIs HOT [plain] [typed|base] — rc 0 when the current event
# is the hot key HOT (FV's ~X~ letter; design P3 §14.4, FPC's menus order):
# an Alt key (FV_EV_KEY kbAlt...) whose typed character (FV_EV_CHAR) equals
# HOT without case, else whose base-layout key (FV_EV_BASE) does; with
# `plain` also a typed character with no Alt / Ctrl (kbChar) that equals HOT
# without case, else whose base key (FV_EV_BASE, else fv.keyboard.layoutBase)
# does. The base key counts only for a typed character that is not ASCII: a
# Latin layout's typed letter (AZERTY's a on the US q key) is never also the
# US position. One key can still match two views when their titles are in
# two scripts (~Ф~айл and ~A~bout: Russian Alt+Ф types ф on the US a key), so
# a hot-key map asks in two passes, `typed` over every view first (only the
# typed character compares), then `base` (only the base key) — the typed
# match wins (§14.4); without either word both compare. Folding is ${c,,} in
# a UTF-8 locale (fv.video._g for a non-ASCII compare from a non-UTF-8
# caller). RESULT is left as it was; a word other than plain / typed / base,
# one twice, or typed with base: rc 2
fv.views.hotKeyIs() {
    if [ "$FV_EV_WHAT" != evKeyDown ] || [[ -z ${1-} ]]; then return 1; fi
    if (( $# > 1 )); then
        # (shift, not "${@:2}": that expansion loses parts under an IFS holding \x01)
        local __fvw_hh=$1
        shift
        fv.views._hkArgs "$@" || return 2
        set -- "$__fvw_hh" "$@"
    fi
    if [[ $1$FV_EV_CHAR == *[![:ascii:]]* && ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then
        fv.video._g fv.views._hotKeyIs "$@"
        return
    fi
    fv.views._hotKeyIs "$@"
}
# hotKeyIs's words: plain, typed, base ([ ]: exact, whatever nocasematch
# says), each at most once, typed and base not both
fv.views._hkArgs() {
    local __fvw_w __fvw_s=' '
    for __fvw_w; do
        if [ "$__fvw_w" != plain ] && [ "$__fvw_w" != typed ] && [ "$__fvw_w" != base ]; then
            fv.views._bad hotKeyIs "'$__fvw_w' is not plain, typed or base"
            return
        fi
        if [[ $__fvw_s == *" $__fvw_w "* ]] || { [ "$__fvw_w" != plain ] && [[ $__fvw_s == *' typed '* || $__fvw_s == *' base '* ]]; }; then
            fv.views._bad hotKeyIs "'${*}': plain once, then typed or base once"
            return
        fi
        __fvw_s+="$__fvw_w "
    done
}
fv.views._hotKeyIs() {   # HOT [plain] [typed|base]
    local __fvw_h=${1,,} __fvw_c=${FV_EV_CHAR,,} __fvw_r __fvw_s=1 __fvw_p='' __fvw_m=''
    shift
    for __fvw_r; do if [ "$__fvw_r" = plain ]; then __fvw_p=1; else __fvw_m=$__fvw_r; fi; done
    case $FV_EV_KEY in
        kbAlt*) ;;
        kbChar) if [[ -z $__fvw_p || -z $__fvw_c ]]; then return 1; fi ;;
        *) return 1 ;;
    esac
    # the typed character (not in the base pass)
    if [ "$__fvw_m" != base ] && [[ -n $__fvw_c && $__fvw_c == "$__fvw_h" ]]; then return 0; fi
    # the base key: not in the typed pass, never for an ASCII typed character
    if [ "$__fvw_m" = typed ] || [[ -n $__fvw_c && $__fvw_c != *[![:ascii:]]* ]]; then return 1; fi
    if [[ -n $FV_EV_BASE ]]; then [[ $FV_EV_BASE == "$__fvw_h" ]]; return; fi
    if [[ $FV_EV_KEY != kbChar ]]; then return 1; fi
    # (a plain character: the tables, loaded at the first such question;
    # >/dev/null: in a subshell layoutBase would print its answer)
    __fvw_r=${RESULT-}
    if fv.keyboard.layoutBase "$FV_EV_CHAR" >/dev/null 2>&1 && [[ $RESULT == "$__fvw_h" ]]; then __fvw_s=0; fi
    RESULT=$__fvw_r
    return "$__fvw_s"
}

# TView.HandleEvent — FV: a mouse-down on a selectable view that is neither
# selected nor disabled focuses it (fv.views.focus; D8 click to focus) and
# is consumed, unless the view took the focus and has ofFirstClick
fv.views._viewEvent() {
    if ! [ "$FV_EV_WHAT" = evMouseDown ]; then return 0; fi
    local -n __fvw_ed=${1}_data
    if (( (${__fvw_ed[State]:-0} & (FV_SF_SELECTED | FV_SF_DISABLED)) == 0 && (${__fvw_ed[Options]:-0} & FV_OF_SELECTABLE) )); then
        if ! fv.views._focus "$1" || [[ -z ${__FV_VW_LIVE[$1]-} ]] || (( ! (${__fvw_ed[Options]:-0} & FV_OF_FIRSTCLICK) )); then
            FV_EV_WHAT=evNothing FV_EV_INFO=$1
        fi
    fi
    return 0
}

# TGroup.HandleEvent — FV: TView's first (click to focus), then, unless that
# handled the event:
#   * focused events (evKeyDown, evCommand): Phase phPreProcess -> each
#     subview with ofPreProcess; phFocused -> Current; phPostProcess -> each
#     subview with ofPostProcess;
#   * positional events (evMouseDown / Up / Move / Auto / Wheel): the
#     front-most visible subview whose rect holds the point (D8);
#   * the rest (evBroadcast and any other name): every subview.
# "Each subview" runs front to back over the list as it was when the event
# came (a view removed or destroyed meanwhile is skipped). Each view is
# reached through the elision; it is skipped WITHOUT A CALL when its
# EventMask lacks the event's bit (FV's masks: a plain TView sees no
# broadcast) or, for a positional or focused event, when it is disabled. The
# loop stops as soon as the event is handled (evNothing). G's Phase is set
# before each call. A handler's rc is ignored (FV procedure).
fv.views._groupEvent() {
    if [ "$FV_EV_WHAT" = evMouseDown ]; then fv.views._viewEvent "$1"; fi
    if [ "${FV_EV_WHAT:-evNothing}" = evNothing ]; then return 0; fi
    local -n __fvw_gl=${1}_views __fvw_gd=${1}_data
    local __fvw_b=${__FV_VW_EVBIT[${FV_EV_WHAT:-evNothing}]-0} __fvw_i __fvw_k __fvw_t
    local -a __fvw_ks
    if (( __fvw_b & (FV_EM_KEYBOARD | FV_EM_COMMAND) )); then
        # one pass over the list as it is now (back to front): the views
        # with ofPreProcess / ofPostProcess (most groups have none)
        local -a __fvw_k1=() __fvw_k2=()
        # (P3 3c, the hot-key map: __fvw_hp the key's pass, its LOCAL copy
        # __FV_VW_HKP the widgets read (a nested dispatch sets its own and
        # gets the outer one back on return); __fvw_hi typed when the owner
        # dispatching this key decided typed (HKN its name: a typed match
        # anywhere in the tree wins, a subgroup asks no base key then);
        # __fvw_hc '+' and the Current the lists were made with, '' without
        # the map; __fvw_q1 / __fvw_q2 the map left out an enabled view in
        # the pre / post phase (1 / " v1  v2 "): G's Phase is set as a full
        # scan leaves it)
        local __fvw_hi=''
        if [ "$__FV_VW_HKP" = typed ] && [ "${__fvw_gd[Owner]-}" = "$__FV_VW_HKN" ]; then __fvw_hi=typed; fi
        local __fvw_hp=$__fvw_hi __fvw_hc='' __fvw_q1='' __fvw_q2='' __FV_VW_HKP=$__fvw_hi __FV_VW_HKN=$1
        # (D21: one test over the live Options of all subviews first: __FV_VW_OEX)
        if [[ -z ${__FV_VW_OEX[$1]+x} ]]; then fv.views._oexpr "$1"; fi
        if (( ${__FV_VW_OEX[$1]} )); then
            # (P3 3c: through the hot-key map when the group has one)
            if [[ -z ${__FV_VW_HKG[$1]-} ]]; then fv.views._hkBuild "$1"; fi
            if (( __FV_VW_HKG[$1] )); then fv.views._hkLists "$1"; __fvw_hc=+${__fvw_gd[Current]-}
            else
                for __fvw_k in "${__fvw_gl[@]}"; do
                    __fvw_t="${__fvw_k}_data[Options]"
                    __fvw_t=${!__fvw_t:-0}
                    if (( __fvw_t & FV_OF_PREPROCESS )); then __fvw_k1+=("$__fvw_k"); fi
                    if (( __fvw_t & FV_OF_POSTPROCESS )); then __fvw_k2+=("$__fvw_k"); fi
                done
            fi
        fi
        if (( ${#__fvw_k1[@]} )); then
            __fvw_ks=("${__fvw_k1[@]}") __FV_VW_HKP=$__fvw_hp
            fv.views._dispatch "$1" phPreProcess "$FV_OF_PREPROCESS" || return 0
        fi
        [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
        if [[ -n $__fvw_q1 ]]; then __fvw_gd[Phase]=phPreProcess; fi
        __fvw_k=${__fvw_gd[Current]-}
        if [[ -n $__fvw_k ]]; then
            __fvw_ks=("$__fvw_k") __FV_VW_HKP=$__fvw_hp
            fv.views._dispatch "$1" phFocused 0 || return 0
        fi
        # (the focus moved meanwhile: a view the map left out of the post
        # list may be focused now)
        if [[ -n $__fvw_q2 ]] && ! [ "$__fvw_hc" = "+${__fvw_gd[Current]-}" ]; then fv.views._hkRefocus; fi
        if (( ${#__fvw_k2[@]} )); then
            __fvw_ks=("${__fvw_k2[@]}") __FV_VW_HKP=$__fvw_hp
            fv.views._dispatch "$1" phPostProcess "$FV_OF_POSTPROCESS" || return 0
        fi
        if [[ -n $__fvw_q2 && -n ${__FV_VW_LIVE[$1]-} ]]; then __fvw_gd[Phase]=phPostProcess; fi
    elif (( __fvw_b & FV_EM_MOUSE )); then
        fv.views._groupMouse "$1"
    else
        __fvw_ks=("${__fvw_gl[@]}")
        fv.views._dispatch "$1" phFocused 0 || :
    fi
    return 0
}

# fv.views._oexpr G — __FV_VW_OEX[G] = the arithmetic test "a subview of G
# has ofPreProcess or ofPostProcess" over their live Options fields (a
# structure cache: dropped by fv.views._restruct)
fv.views._oexpr() {
    local -n __fvw_ol=${1}_views
    local __fvw_k __fvw_e=''
    for __fvw_k in "${__fvw_ol[@]}"; do __fvw_e+="${__fvw_k}_data[Options] | "; done
    __FV_VW_OEX[$1]="($__fvw_e 0) & $(( FV_OF_PREPROCESS | FV_OF_POSTPROCESS ))"
}

# ---- the hot-key map (P3 stage 3c, design §3.1, 10.3b; the state block: HKS) ----
# fv.views._hkLists G [1] — TGroup.HandleEvent's pre / post lists (its locals
# __fvw_gl, __fvw_k1, __fvw_k2, __fvw_hp, __fvw_q1, __fvw_q2) through G's
# hot-key map, in FV's Z order: every view with ofPreProcess / ofPostProcess
# as before, except that a MAPPED view (its handler a body of HKS) that is
# not focused is taken only when the key names it (the pre phase: Alt keys;
# the post phase: Alt keys and plain letters) — its built-in handler reacts
# to nothing else there. An enabled view left out is noted (__fvw_q1 = 1 for
# the pre phase, __fvw_q2 += " v " for the post one): the caller sets G's
# Phase as the full scan's call would have, and a view focused meanwhile
# joins the post list (fv.views._hkRefocus). Before a mapped view is skipped
# its text is compared with the stamp it was mapped from: a direct field
# write rebuilds the map once and the lists start again (the 1: no second
# rebuild)
fv.views._hkLists() {
    local __fvw_k __fvw_t __fvw_r __fvw_s __fvw_e __fvw_n1 __fvw_n2 __fvw_hs='' IFS=' '
    fv.views._hkNames "$1"
    # (a typed-named view whose text changed since the map: rebuilt once)
    if [[ -n $__fvw_hs && -z ${2-} ]]; then
        fv.views._hkDirty
        fv.views._hkBuild "$1"
        fv.views._hkLists "$1" 1
        return 0
    fi
    for __fvw_k in "${__fvw_gl[@]}"; do
        __fvw_t="${__fvw_k}_data[Options]"
        __fvw_t=${!__fvw_t:-0}
        if (( ! (__fvw_t & (FV_OF_PREPROCESS | FV_OF_POSTPROCESS)) )); then continue; fi
        __fvw_r=${__FV_VW_HKR[$__fvw_k]-}
        if [[ -n $__fvw_r ]]; then
            __fvw_e="${__fvw_k}_data[State]"
            __fvw_e=${!__fvw_e:-0}
            if (( ! (__fvw_e & FV_SF_FOCUSED) )); then
                # (named: the case-sensitive test, whatever nocasematch says)
                if [ "${__fvw_n2#*" $__fvw_k "}" = "$__fvw_n2" ]; then
                    if [[ $__fvw_r == *'[@]' ]]; then __fvw_s=${!__fvw_r@Q}; else __fvw_s=${!__fvw_r-}; fi
                    if [ "$__fvw_s" = "${__FV_VW_HKT[$__fvw_k]-}" ] || [[ -n ${2-} ]]; then
                        if (( ! (__fvw_e & FV_SF_DISABLED) )); then
                            if (( __fvw_t & FV_OF_PREPROCESS )); then __fvw_q1=1; fi
                            if (( __fvw_t & FV_OF_POSTPROCESS )); then __fvw_q2+=" $__fvw_k "; fi
                        fi
                        continue
                    fi
                    __fvw_k1=() __fvw_k2=() __fvw_q1='' __fvw_q2=''
                    fv.views._hkDirty
                    fv.views._hkBuild "$1"
                    fv.views._hkLists "$1" 1
                    return 0
                fi
                if (( __fvw_t & FV_OF_PREPROCESS )); then
                    if ! [ "${__fvw_n1#*" $__fvw_k "}" = "$__fvw_n1" ]; then __fvw_k1+=("$__fvw_k")
                    elif (( ! (__fvw_e & FV_SF_DISABLED) )); then __fvw_q1=1; fi
                fi
                if (( __fvw_t & FV_OF_POSTPROCESS )); then __fvw_k2+=("$__fvw_k"); fi
                continue
            fi
        fi
        if (( __fvw_t & FV_OF_PREPROCESS )); then __fvw_k1+=("$__fvw_k"); fi
        if (( __fvw_t & FV_OF_POSTPROCESS )); then __fvw_k2+=("$__fvw_k"); fi
    done
}
# fv.views._hkRefocus — (TGroup.HandleEvent's locals; rare) G's Current
# changed during the pre / focused phase: when the new Current is a view the
# map left out of the post list (__fvw_q2) it is focused now, and the full
# scan would call it there (a focused widget reacts to Space / Enter /
# arrows): it joins __fvw_k2 in G's order
fv.views._hkRefocus() {
    local __fvw_c=${__fvw_gd[Current]-} __fvw_v __fvw_o=' '
    if [[ -z $__fvw_c ]] || [ "${__fvw_q2#*" $__fvw_c "}" = "$__fvw_q2" ]; then return 0; fi
    for __fvw_v in "${__fvw_k2[@]}"; do __fvw_o+="$__fvw_v "; done
    __fvw_k2=()
    for __fvw_v in "${__fvw_gl[@]}"; do
        if [ "$__fvw_v" = "$__fvw_c" ] || ! [ "${__fvw_o#*" $__fvw_v "}" = "$__fvw_o" ]; then __fvw_k2+=("$__fvw_v"); fi
    done
}
# fv.views._hkNames G — the caller's __fvw_n1 / __fvw_n2 (the views of G the
# key names for the pre / the post phase: " v1  v2 ") and __fvw_hp (the pass):
# only an evKeyDown of an Alt key or a plain character (kbChar) names views.
# As fv.views.hotKeyIs (design §14.4: typed over every view first, then
# base), the typed character (folded) first — the views mapped with it that
# can react (fv.views._hkLive): pass typed —, else, for a typed character
# that is not ASCII (or none), the base-layout key (FV_EV_BASE; a plain
# character: the layout tables, fv.keyboard.layoutBase): pass base. Plain
# characters name views for the post phase only (FV: a plain hot letter
# counts in phPostProcess; a focused view is called anyway). In a subgroup
# whose owner decided typed (the caller's __fvw_hi) there is no base pass.
# (P3 3h) Any other key names the views mapped with it by HKK (HOT[G:#KEY],
# both phases, no pass): THistory for kbDown / kbCtrlX
fv.views._hkNames() {
    __fvw_n1='' __fvw_n2='' __fvw_hp=$__fvw_hi
    if [ "$FV_EV_WHAT" != evKeyDown ]; then return 0; fi
    if [[ $FV_EV_KEY != kbAlt* && $FV_EV_KEY != kbChar ]]; then
        __fvw_n2=${__FV_VW_HOT["$1:#${FV_EV_KEY-}"]-} __fvw_n1=${__FV_VW_HOT["$1:#${FV_EV_KEY-}"]-}
        return 0
    fi
    if [[ $FV_EV_CHAR == *[![:ascii:]]* && ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g fv.views._hkNamesX "$1"; return 0; fi
    fv.views._hkNamesX "$1"
}
fv.views._hkNamesX() {
    local __fvw_c=${FV_EV_CHAR,,} __fvw_b __fvw_n='' __fvw_r
    if [[ -n $__fvw_c ]]; then __fvw_n=${__FV_VW_HOT["$1:$__fvw_c"]-}; fi
    if [[ -n $__fvw_n ]]; then fv.views._hkLive "$__fvw_c"; fi
    if [[ -n $__fvw_n ]]; then __fvw_hp=typed
    elif [[ -z $__fvw_hi ]] && [[ -z $__fvw_c || $__fvw_c == *[![:ascii:]]* ]]; then
        __fvw_b=${FV_EV_BASE-}
        if [[ -z $__fvw_b && -n $__fvw_c ]] && [ "$FV_EV_KEY" = kbChar ]; then
            # (>/dev/null: in a subshell layoutBase would print its answer)
            __fvw_r=${RESULT-}
            if fv.keyboard.layoutBase "$FV_EV_CHAR" >/dev/null 2>&1; then __fvw_b=$RESULT; fi
            RESULT=$__fvw_r
        fi
        if [[ -n $__fvw_b ]]; then
            __fvw_n=${__FV_VW_HOT["$1:${__fvw_b,,}"]-}
            if [[ -n $__fvw_n ]]; then __fvw_hp=base; fi
        fi
    fi
    __fvw_n2=$__fvw_n
    if [ "$FV_EV_KEY" != kbChar ]; then __fvw_n1=$__fvw_n; fi
}
# fv.views._hkLive K — the caller's __fvw_n (the views mapped with the typed
# letter K) cut to the views that can react to it (a disabled view never
# matches): not disabled; focused or with an option of a phase the key
# counts in (an Alt key: ofPreProcess or ofPostProcess; a plain character:
# ofPostProcess); for a body with an item test (HKE), its first text with K
# enabled (TCluster: that item's EnableMask bit). An empty answer sends the
# key to the base pass
fv.views._hkLive() {
    local __fvw_v __fvw_o='' __fvw_x __fvw_m=$(( FV_OF_PREPROCESS | FV_OF_POSTPROCESS )) IFS=' '
    if [ "$FV_EV_KEY" = kbChar ]; then __fvw_m=$FV_OF_POSTPROCESS; fi
    # (the names are kklass identifiers: no glob character to expand)
    for __fvw_v in $__fvw_n; do
        __fvw_x="${__fvw_v}_data[State]"
        __fvw_x=${!__fvw_x:-0}
        if (( __fvw_x & FV_SF_DISABLED )); then continue; fi
        if (( ! (__fvw_x & FV_SF_FOCUSED) )); then
            __fvw_x="${__fvw_v}_data[Options]"
            if (( ! (${!__fvw_x:-0} & __fvw_m) )); then continue; fi
        fi
        __fvw_x=${__FV_VW_HKI["$__fvw_v:$1"]-}
        if [[ -n $__fvw_x ]] && ! "${__FV_VW_HKF[$__fvw_v]-:}" "$__fvw_v" "$__fvw_x"; then continue; fi
        # (its text as mapped: a direct write since then may have taken the
        # letter away — the caller rebuilds the map: __fvw_hs)
        __fvw_x=${__FV_VW_HKR[$__fvw_v]-}
        if [[ -n $__fvw_x ]]; then
            if [[ $__fvw_x == *'[@]' ]]; then __fvw_x=${!__fvw_x@Q}; else __fvw_x=${!__fvw_x-}; fi
            if ! [ "$__fvw_x" = "${__FV_VW_HKT[$__fvw_v]-}" ]; then __fvw_hs=1; continue; fi
        fi
        __fvw_o+=" $__fvw_v "
    done
    __fvw_n=$__fvw_o
}
# fv.views._hkBuild G — G's map: every subview whose class's HandleEvent is a
# body registered in HKS (a class that overrides HandleEvent is never mapped)
fv.views._hkBuild() {
    local -n __fvw_hl=${1}_views
    local __fvw_k __fvw_f __fvw_r IFS=' '
    __FV_VW_HKG[$1]=0
    for __fvw_k in "${__fvw_hl[@]}"; do
        # (one simple command: the assignments run in order)
        __fvw_f=${__fvw_k}_class __fvw_f="${!__fvw_f-}_class_method_owner[HandleEvent]" __fvw_f=${__FV_VW_IMPL[${!__fvw_f-}.HandleEvent]-}
        __fvw_r=${__FV_VW_HKS[${__fvw_f:-.}]-}
        if [[ -z $__fvw_r ]]; then continue; fi
        fv.views._hkView "$1" "$__fvw_k" "$__fvw_k$__fvw_r" "$__fvw_f"
        __FV_VW_HKG[$1]=1
    done
}
# fv.views._hkView G V REF BODY — V's hot letters into G's map (FV HotKey:
# the character after the first `~` of each text, folded), its stamp kept;
# for a BODY with an item test (HKE) the index of V's first text with each
# letter (HKI) and the test (HKF)
fv.views._hkView() {
    local __fvw_s __fvw_x __fvw_l __fvw_e=${__FV_VW_HKE[${4:-.}]-} __fvw_i=-1
    local -a __fvw_tx
    if [[ $3 == *'[@]' ]]; then
        local -n __fvw_ha=${3%'[@]'}
        __fvw_tx=("${__fvw_ha[@]}") __fvw_s=${!3@Q}
    else
        __fvw_s=${!3-}
        __fvw_tx=("$__fvw_s")
    fi
    __FV_VW_HKR[$2]=$3 __FV_VW_HKT[$2]=$__fvw_s
    if [[ -n $__fvw_e ]]; then __FV_VW_HKF[$2]=$__fvw_e; fi
    for __fvw_x in "${__fvw_tx[@]}"; do
        __fvw_i=$(( __fvw_i + 1 ))
        __fvw_l=${__fvw_x#*'~'}
        if [ "$__fvw_l" = "$__fvw_x" ] || [[ -z $__fvw_l ]]; then continue; fi
        if [[ $__fvw_l == [![:ascii:]]* && ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then fv.video._g fv.views._hkLetter "$__fvw_l"
        else __fvw_l=${__fvw_l:0:1} __fvw_l=${__fvw_l,,}; fi
        __fvw_x=${__FV_VW_HOT["$1:$__fvw_l"]-}
        if [ "${__fvw_x#*" $2 "}" = "$__fvw_x" ]; then
            __FV_VW_HOT["$1:$__fvw_l"]+=" $2 "
            if [[ -n $__fvw_e ]]; then __FV_VW_HKI["$2:$__fvw_l"]=$__fvw_i; fi
        fi
    done
    # (P3 3h: the keys that name V without a hot letter, HOT[G:#KEY])
    if [[ -n ${__FV_VW_HKK[${4:-.}]-} ]]; then
        local IFS=' '
        # (key names: no glob character to expand)
        for __fvw_x in ${__FV_VW_HKK[$4]}; do __FV_VW_HOT["$1:#$__fvw_x"]+=" $2 "; done
    fi
}
# (the first character, folded, in fv.video's UTF-8 locale: _hkView's __fvw_l)
fv.views._hkLetter() { __fvw_l=${1:0:1} __fvw_l=${__fvw_l,,}; }
# fv.views._hkDirty [G] — every hot-key map dropped (rebuilt at the next key
# of each group): the setters' entry (fv.dialogs.setTitle, setLabel,
# setItems). G is accepted for the callers' sake: one table holds all maps,
# and dropping it whole is cheaper than finding one group's keys. RESULT kept
fv.views._hkDirty() {
    __FV_VW_HOT=() __FV_VW_HKG=() __FV_VW_HKR=() __FV_VW_HKT=() __FV_VW_HKI=() __FV_VW_HKF=()
}
# fv.views._hk HOT PLAIN [VIEW] — the widgets' hot-key test (a friend entry
# for fv.dialogs): fv.views.hotKeyIs HOT [plain] in the pass the hot-key map
# decided for this key (HKP: the innermost TGroup.HandleEvent's) when VIEW is
# a mapped view (or not given). A view the map does not know (a class that
# overrides HandleEvent and calls the body with `inherited`) asks in the
# typed pass too (a typed match somewhere wins: no base match anywhere), but
# without a pass otherwise: the map could not see its typed letter, so it
# compares both, as in a full scan. PLAIN 1 allows the plain letter (the
# caller's phase rule). RESULT kept
fv.views._hk() {
    if [ "$FV_EV_WHAT" != evKeyDown ] || [[ -z ${1-} ]]; then return 1; fi
    local -a __fvw_ha=("$1")
    if [ "${2-}" = 1 ]; then __fvw_ha+=(plain); fi
    if [[ -n $__FV_VW_HKP ]] && [[ -z ${3-} || -n ${__FV_VW_HKR[$3]-} || $__FV_VW_HKP == typed ]]; then __fvw_ha+=("$__FV_VW_HKP"); fi
    if [[ $1$FV_EV_CHAR == *[![:ascii:]]* && ${#__FV_VS_P}${#__FV_VS_B} != 11 ]]; then
        fv.video._g fv.views._hotKeyIs "${__fvw_ha[@]}"
        return
    fi
    fv.views._hotKeyIs "${__fvw_ha[@]}"
}

# fv.views._groupMouse G — TGroup.HandleEvent's positional event (its
# locals): the front-most visible subview whose rect holds the point gets
# it (apart because bash copies a function's body on every call)
fv.views._groupMouse() {
    local __fvw_i __fvw_k
    __fvw_ks=("${__fvw_gl[@]}")
    for (( __fvw_i = ${#__fvw_ks[@]} - 1; __fvw_i >= 0; __fvw_i-- )); do
        __fvw_k=${__fvw_ks[__fvw_i]}
        local -n __fvw_kd=${__fvw_k}_data
        if (( (${__fvw_kd[State]:-0} & FV_SF_VISIBLE) && FV_EV_MOUSE_X >= __FV_VW_AX[$__fvw_k] && FV_EV_MOUSE_Y >= __FV_VW_AY[$__fvw_k] )) \
           && (( FV_EV_MOUSE_X < __FV_VW_AX[$__fvw_k] + ${__fvw_kd[SizeX]:-0} && FV_EV_MOUSE_Y < __FV_VW_AY[$__fvw_k] + ${__fvw_kd[SizeY]:-0} )); then
            __fvw_ks=("$__fvw_k")
            fv.views._dispatch "$1" phFocused 0 || :
            return 0
        fi
    done
}

# fv.views._dispatch G PHASE OPTION — FV's DoHandleEvent for each view of
# the caller's __fvw_ks, front to back (its last element first): rc 1 as soon
# as the event is handled or G is gone (stop). A view is skipped without a
# call when its EventMask lacks the event's bit (read first: the cheapest
# test, and a destroyed view has no mask), it is no longer a live subview of
# G, it lacks OPTION (the pre / post phase) or it is disabled for a
# positional / focused event; else G's Phase = PHASE and the view's
# HandleEvent through the elision, inline: TView's body does nothing but a
# mouse-down's click to focus, so it is not even called for anything else;
# a broadcast skips a built-in handler whose row in the broadcast table
# (__FV_VW_BCAST) does not list the command (a group: when fv.views._quiet
# finds its subtree quiet too)
fv.views._dispatch() {
    local __fvw_xi __fvw_xk __fvw_xb __fvw_xf __fvw_xr __fvw_xt
    local -n __fvw_xg=${1}_data
    __fvw_xb=${__FV_VW_EVBIT[${FV_EV_WHAT:-evNothing}]-0}
    for (( __fvw_xi = ${#__fvw_ks[@]} - 1; __fvw_xi >= 0; __fvw_xi-- )); do
        if [ "$FV_EV_WHAT" = evNothing ] || [[ -z ${__FV_VW_LIVE[$1]-} ]]; then return 1; fi
        __fvw_xk=${__fvw_ks[__fvw_xi]}
        # (D21: the skip tests merged: a destroyed view, the EventMask, no longer
        # G's, the pre / post option, disabled for a positional / focused event)
        if [[ -z ${__FV_VW_LIVE[$__fvw_xk]-} ]]; then continue; fi
        local -n __fvw_xd=${__fvw_xk}_data
        if (( ! (__fvw_xb & ${__fvw_xd[EventMask]:-0}) || ($3 && ! (${__fvw_xd[Options]:-0} & $3)) \
              || ((${__fvw_xd[State]:-0} & FV_SF_DISABLED) && (__fvw_xb & (FV_EM_MOUSE | FV_EM_KEYBOARD | FV_EM_COMMAND))) )) \
           || ! [ "${__fvw_xd[Owner]-}" = "$1" ]; then continue; fi
        # (one simple command: the assignments run in order)
        __fvw_xf=${__fvw_xk}_class __fvw_xf="${!__fvw_xf-}_class_method_owner[HandleEvent]" __fvw_xf=${__FV_VW_IMPL[${!__fvw_xf-}.HandleEvent]-}
        if (( __fvw_xb == FV_EM_BROADCAST )); then
            # (stage 3b, P3-4: the list moving its own vertical bar is not
            # told back — that bar's cmScrollBarChanged only)
            if [[ -n $__FV_VW_QX ]] && [ "$__fvw_xk" = "$__FV_VW_QX" ] && [ "$FV_EV_COMMAND" = cmScrollBarChanged ]; then
                __fvw_xt="${__fvw_xk}_data[VScrollBar]"
                if [ "$FV_EV_INFO" = "${!__fvw_xt-}" ]; then continue; fi
            fi
            # (stage 3a-2, the broadcast table: a built-in handler whose row
            # does not list the command is skipped without a call — a leaf at
            # once, a built-in group when its subtree has no listener either:
            # the delivery is skipped, its Phase effects kept: fv.views._quiet)
            if [[ -n $__fvw_xf && -n ${__FV_VW_BCAST[$__fvw_xf]+x}${__FV_VW_QGRP[$__fvw_xf]-} ]] \
               && [[ " ${__FV_VW_BCAST[$__fvw_xf]-} " != *" $FV_EV_COMMAND "* ]]; then
                if [[ -z ${__FV_VW_GRP[$__fvw_xk]-} ]]; then continue; fi
                if fv.views._quiet "$__fvw_xk" "$FV_EV_COMMAND" "$FV_EV_INFO"; then __fvw_xg[Phase]=$2; continue; fi
            fi
        # (TView's and TFrame's handlers react to a mouse-down only)
        elif { [ "$__fvw_xf" = fv.views._viewEvent ] || [ "$__fvw_xf" = fv.views._frameEvent ]; } && ! [ "$FV_EV_WHAT" = evMouseDown ]; then continue; fi
        __fvw_xg[Phase]=$2
        if [[ -z $__fvw_xf ]]; then "$__fvw_xk.HandleEvent" || :
        else
            __fvw_xr=${RESULT-}
            "$__fvw_xf" "$__fvw_xk" || :
            RESULT=$__fvw_xr
        fi
        # (a handler may change the event's kind: FV reads Event.What anew)
        __fvw_xb=${__FV_VW_EVBIT[${FV_EV_WHAT:-evNothing}]-0}
    done
    if [ "$FV_EV_WHAT" = evNothing ]; then return 1; fi
    return 0
}

# fv.views._quiet V COMMAND INFO — rc 0 when the broadcast COMMAND (from
# INFO, FV's InfoPtr) delivered to V
# would reach no handler that reacts to it (stage 2c-p: the focus broadcasts
# of a window switch cost a dispatch tree each). Stage 3a-2: the answer
# comes from the broadcast table __FV_VW_BCAST. V's HandleEvent is a built-in
# body with a row (a QGRP entry: the row '') that does not list COMMAND
# (TView's, TFrame's, TGroup's: ''; TWindow's: cmSelectWindowNum), and, for
# a group, every subview the dispatch would reach (EventMask with
# evBroadcast, live, still V's subview) is quiet itself. A user override
# anywhere in the way is never quiet, nor is a built-in body without a row.
# The dispatch sets a group's Phase before each subview it calls (not before
# a handler the table skips): when the answer is 0 the walk sets those Phases
# the same way (only then: a walk that ends "not quiet" leaves no trace), so
# a skipped delivery leaves the same state. A built-in HandleEvent that
# reacts to a broadcast lists it in its row. NESTED (a 4th word, internal):
# the inner walk adds the groups to stamp to the outer call's __fvw_qp
fv.views._quiet() {
    local __fvw_f=${1}_class
    if [[ -z ${4-} ]]; then local -a __fvw_qp=(); fi
    __fvw_f="${!__fvw_f-}_class_method_owner[HandleEvent]"
    __fvw_f=${__FV_VW_IMPL[${!__fvw_f-}.HandleEvent]-}
    # (the broadcast table: a user override, a built-in handler without a row
    # and a row that lists COMMAND are not quiet; a leaf otherwise is)
    if [[ -z $__fvw_f || -z ${__FV_VW_BCAST[$__fvw_f]+x}${__FV_VW_QGRP[$__fvw_f]-} ]] \
       || [[ " ${__FV_VW_BCAST[$__fvw_f]-} " == *" $2 "* ]]; then return 1; fi
    if [[ -z ${__FV_VW_GRP[$1]-} ]]; then return 0; fi
    local -n __fvw_ql=${1}_views
    local __fvw_k __fvw_t __fvw_p=0
    for __fvw_k in "${__fvw_ql[@]}"; do
        __fvw_t="${__fvw_k}_data[EventMask]"
        if (( ! (${!__fvw_t:-0} & FV_EM_BROADCAST) )) || [[ -z ${__FV_VW_LIVE[$__fvw_k]-} ]]; then continue; fi
        __fvw_t="${__fvw_k}_data[Owner]"
        if ! [ "${!__fvw_t-}" = "$1" ]; then continue; fi
        # (a leaf: quiet when its handler is built-in and its row does not
        # list COMMAND, as the dispatch skips it; a group is looked into)
        if [[ -z ${__FV_VW_GRP[$__fvw_k]-} ]]; then
            # (stage 3b, P3-4: the list moving its own vertical bar counts as
            # quiet for that bar's cmScrollBarChanged)
            if [[ -n $__FV_VW_QX ]] && [ "$__fvw_k" = "$__FV_VW_QX" ] && [ "$2" = cmScrollBarChanged ]; then
                __fvw_t="${__fvw_k}_data[VScrollBar]"
                if [ "${3-}" = "${!__fvw_t-}" ]; then continue; fi
            fi
            __fvw_t=${__fvw_k}_class
            __fvw_t="${!__fvw_t-}_class_method_owner[HandleEvent]"
            __fvw_t=${__FV_VW_IMPL[${!__fvw_t-}.HandleEvent]-}
            if [[ -n $__fvw_t && -n ${__FV_VW_BCAST[$__fvw_t]+x}${__FV_VW_QGRP[$__fvw_t]-} ]] \
               && [[ " ${__FV_VW_BCAST[$__fvw_t]-} " != *" $2 "* ]]; then continue; fi
            return 1
        fi
        fv.views._quiet "$__fvw_k" "$2" "${3-}" NESTED || return 1
        __fvw_p=1
    done
    if (( __fvw_p )); then __fvw_qp+=("$1"); fi
    if [[ -z ${4-} ]]; then
        for __fvw_k in "${__fvw_qp[@]}"; do printf -v "${__fvw_k}_data[Phase]" '%s' phFocused; done
    fi
    return 0
}

# fv.views.message V WHAT COMMAND [INFO] — FV Message(Receiver, What,
# Command, InfoPtr): a new event (FV_EV_WHAT=WHAT, FV_EV_COMMAND=COMMAND,
# FV_EV_INFO=INFO, the other fields empty) to V's HandleEvent through the
# elision; the caller's event is put back afterwards. rc 0 and RESULT = the
# handler (FV_EV_INFO after the call: clearEvent puts the handler there)
# when the event was handled; rc 1 and RESULT='' when nobody handled it, and
# for V '' (FV's nil receiver). WHAT: an event name
fv.views.message() {
    if (( $# != 3 && $# != 4 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    if [[ -z $1 ]]; then RESULT=''; return 1; fi
    fv.views._view "$1" message || return
    if [[ -z $2 || $2 == *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]* ]]; then
        fv.views._bad message 'WHAT must be an event name (evBroadcast, evCommand, ...)'; return
    fi
    fv.views._message "$1" "$2" "$3" "${4-}"
}
fv.views._message() {   # V WHAT COMMAND INFO [ID] (ID: FV NewMessage's, P3 3b)
    # (a broadcast that no handler would see: not delivered, nobody handles it)
    if [ "$2" = evBroadcast ] && fv.views._quiet "$1" "$3" "$4"; then RESULT=''; return 1; fi
    local -a __fvw_es
    local __fvw_a='' __fvw_s=1
    fv.views._evSave
    FV_EV_WHAT=$2 FV_EV_KEY='' FV_EV_CHAR='' FV_EV_COMMAND=$3 FV_EV_ID=${5-} FV_EV_INFO=$4
    FV_EV_MOUSE_X=0 FV_EV_MOUSE_Y=0 FV_EV_MOUSE_BUTTONS=0 FV_EV_MOUSE_MODS=0
    FV_EV_MOUSE_DOUBLE=0 FV_EV_MOUSE_TRIPLE=0 FV_EV_WHEEL=0 FV_EV_EOF=0
    fv.views._virt "$1" HandleEvent || :
    if [ "$FV_EV_WHAT" = evNothing ]; then __fvw_a=$FV_EV_INFO __fvw_s=0; fi
    fv.views._evRestore
    RESULT=$__fvw_a
    return "$__fvw_s"
}

# ---- state (FV SetState) --------------------------------------------------------

# fv.views.setState V BIT ENABLE — FV SetState(AState, Enable) through the
# elision (an override of yours runs; `inherited SetState "$@"` reaches the
# built-in): BIT one FV_SF_* value, ENABLE 1 or 0. RESULT is kept; rc 0
# (the body's rc is ignored: FV procedure)
fv.views.setState() {
    if (( $# != 3 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" setState || return
    if [[ -z $2 || $2 == *[!0123456789]* || ${#2} -gt 9 ]] || ! [[ $3 == [01] ]]; then
        fv.views._bad setState 'BIT must be a number (FV_SF_*), ENABLE 1 or 0'; return
    fi
    fv.views._virt "$1" SetState "$(( 10#$2 ))" "$3" || :
    return 0
}

# TView.SetState BIT ENABLE — FV: the bit set or cleared; then, when V has an
# owner: sfVisible -> DrawShow (V drawn with its shadow) / DrawHide (its
# area, shadow included, repainted from below) and the owner's ResetCurrent
# for a selectable V; sfCursorVis / sfCursorIns -> the cursor (resetCursor)
# when V is focused; sfShadow -> V's area with the shadow repainted from
# below; sfFocused -> resetCursor and the broadcast cmReceivedFocus /
# cmReleasedFocus to the owner (FV_EV_INFO = V). Any other bit: only the bit
# (sfExposed is read on the root only: 2c-2)
fv.views._viewSetState() {
    local -n __fvw_sd=${1}_data
    local __fvw_o=${__fvw_sd[Owner]-}
    if (( $3 )); then __fvw_sd[State]=$(( ${__fvw_sd[State]:-0} | $2 )); else __fvw_sd[State]=$(( ${__fvw_sd[State]:-0} & ~$2 )); fi
    [[ -n $__fvw_o ]] || return 0
    if (( $2 == FV_SF_FOCUSED )); then
        fv.views._cursorLater "$1"
        if (( $3 )); then fv.views._message "$__fvw_o" evBroadcast cmReceivedFocus "$1" || :
        else fv.views._message "$__fvw_o" evBroadcast cmReleasedFocus "$1" || :; fi
    elif (( $2 == FV_SF_VISIBLE || $2 == FV_SF_CURSORVIS || $2 == FV_SF_CURSORINS || $2 == FV_SF_SHADOW )); then
        fv.views._viewSetStateX "$@"
    fi
    return 0
}
# fv.views._viewSetStateX V BIT ENABLE — TView.SetState's sfVisible,
# sfCursorVis / sfCursorIns and sfShadow effects (V has an owner, the bit is
# set); apart from the frequent bits (bash copies a function's body per call)
fv.views._viewSetStateX() {
    local -n __fvw_sd=${1}_data
    local __fvw_o=${__fvw_sd[Owner]-} __fvw_r1 __fvw_r2 __fvw_r3 __fvw_r4
    if (( $2 == FV_SF_VISIBLE )); then
        if (( $3 )); then fv.views._drawView "$1"
        else
            fv.views._srect "$1"
            fv.views._drawUnder "$__fvw_o" "$__fvw_r1" "$__fvw_r2" "$__fvw_r3" "$__fvw_r4"
        fi
        if (( ${__fvw_sd[Options]:-0} & FV_OF_SELECTABLE )); then fv.views._resetCurrent "$__fvw_o"; fi
    elif (( $2 == FV_SF_CURSORVIS || $2 == FV_SF_CURSORINS )); then
        if (( ${__fvw_sd[State]:-0} & FV_SF_FOCUSED )); then fv.views._cursorLater "$1"; fi
    elif (( $2 == FV_SF_SHADOW )); then
        fv.views._abs "$1"
        fv.views._drawUnder "$__fvw_o" "$__fvw_r1" "$__fvw_r2" "$(( __fvw_r3 + 2 ))" "$(( __fvw_r4 + 1 ))"
    fi
    return 0
}

# TGroup.SetState BIT ENABLE — FV: TView's; then sfActive / sfDragging ->
# each subview's SetState (front to back) and, instead of FV's Lock /
# Unlock that redraws the whole group (D17), the border-only redraw of each
# subview TFrame whose bit changed (fv.views._frameBorder: 4 writes);
# sfFocused -> Current's SetState (the focus chain)
fv.views._groupSetState() {
    fv.views._viewSetState "$@"
    if (( $2 == FV_SF_ACTIVE || $2 == FV_SF_DRAGGING )); then
        if [[ -n ${__FV_VW_GRP[$1]-} ]]; then fv.views._groupActive "$@"; fi
    elif (( $2 == FV_SF_FOCUSED )); then
        local -n __fvw_sg=${1}_data
        local __fvw_c=${__fvw_sg[Current]-}
        if [[ -n $__fvw_c && -n ${__FV_VW_LIVE[$__fvw_c]-} ]]; then fv.views._virt "$__fvw_c" SetState "$FV_SF_FOCUSED" "$3" || :; fi
    fi
    return 0
}
# fv.views._groupActive G BIT ENABLE — TGroup.SetState's sfActive /
# sfDragging part: each subview's SetState, then the border-only redraw of
# each subview TFrame whose bit changed (fv.views._frameBorder)
fv.views._groupActive() {
    local -n __fvw_sl=${1}_views
    local -a __fvw_ks=("${__fvw_sl[@]}") __fvw_fs=()
    local __fvw_i __fvw_k __fvw_b
    __FV_VW_LSU=$(( __FV_VW_LSU + 1 ))
    for (( __fvw_i = ${#__fvw_ks[@]} - 1; __fvw_i >= 0; __fvw_i-- )); do
        __fvw_k=${__fvw_ks[__fvw_i]}
        fv.views._kid "$1" "$__fvw_k" || continue
        local -n __fvw_gk=${__fvw_k}_data
        __fvw_b=$(( ${__fvw_gk[State]:-0} & $2 ))
        fv.views._virt "$__fvw_k" SetState "$2" "$3" || :
        if [[ -n ${__FV_VW_FRM[$__fvw_k]-} && -n ${__FV_VW_LIVE[$__fvw_k]-} ]] && (( (${__fvw_gk[State]:-0} & $2) != __fvw_b )); then
            __fvw_fs+=("$__fvw_k")
        fi
    done
    for __fvw_k in "${__fvw_fs[@]}"; do
        if fv.views._kid "$1" "$__fvw_k"; then fv.views._frameBorder "$__fvw_k"; fi
    done
    fv.views._release
    return 0
}

# ---- focus (FV Select, Focus, FocusNext, SelectNext) ------------------------------

# fv.views.select V — FV Select: a selectable V becomes its owner's Current;
# with ofTopSelect it is brought to the front (makeFirst), whose
# ResetCurrent makes it Current. Not selectable or without an owner:
# nothing. The changed parts are redrawn (a window that was covered: whole;
# else the two frame borders). RESULT is kept
fv.views.select() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" select || return
    fv.views._select "$1"
}
fv.views._select() {
    local -n __fvw_cd=${1}_data
    local __fvw_op=${__fvw_cd[Options]:-0} __fvw_o=${__fvw_cd[Owner]-}
    if (( ! (__fvw_op & FV_OF_SELECTABLE) )) || [[ -z $__fvw_o ]]; then return 0; fi
    if (( __fvw_op & FV_OF_TOPSELECT )); then
        local -n __fvw_cl=${__fvw_o}_views
        fv.views.putInFrontOf "$1" "${__fvw_cl[-1]}" || :
        # (deviation: FV's MakeFirst is a no-op for a view already in front,
        # which then stays unselected when another view is Current; only a
        # visible, enabled view is made Current here, as FV's PutInFrontOf
        # resets Current for a visible view only)
        if [[ -z ${__FV_VW_LIVE[$1]-} || -z ${__FV_VW_LIVE[$__fvw_o]-} ]]; then return 0; fi
        local -n __fvw_co=${__fvw_o}_data
        if ! [ "${__fvw_co[Current]-}" = "$1" ] \
           && (( (${__fvw_cd[State]:-0} & (FV_SF_VISIBLE | FV_SF_DISABLED)) == FV_SF_VISIBLE )); then
            fv.views._setCurrent "$__fvw_o" "$1"
        fi
    else
        fv.views._setCurrent "$__fvw_o" "$1"
    fi
    return 0
}

# fv.views.focus V — FV Focus: rc 0 when V is (or now is) on the focus
# chain: a view already selected or modal answers at once; else its owner is
# focused first (recursively), then V is selected unless the owner's
# Current has ofValidate and its Valid(cmReleasedFocus) says no (rc 1).
# RESULT is kept
fv.views.focus() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" focus || return
    local __fvw_rr=${RESULT-} __fvw_s=0
    fv.views._focus "$1" || __fvw_s=$?
    RESULT=$__fvw_rr
    return "$__fvw_s"
}
fv.views._focus() {
    local -n __fvw_fd=${1}_data
    if (( ${__fvw_fd[State]:-0} & (FV_SF_SELECTED | FV_SF_MODAL) )); then return 0; fi
    local __fvw_o=${__fvw_fd[Owner]-} __fvw_c
    if [[ -z $__fvw_o ]]; then return 0; fi
    fv.views._focus "$__fvw_o" || return 1
    local -n __fvw_fo=${__fvw_o}_data
    __fvw_c=${__fvw_fo[Current]-}
    if [[ -n $__fvw_c && -n ${__FV_VW_LIVE[$__fvw_c]-} ]]; then
        local -n __fvw_fc=${__fvw_c}_data
        if (( ${__fvw_fc[Options]:-0} & FV_OF_VALIDATE )); then
            fv.views._virt "$__fvw_c" Valid cmReleasedFocus || return 1
        fi
    fi
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 1
    fv.views._select "$1"
}

# fv.views._findNext G FORWARDS — FV FindNext: the caller's __fvw_n = from
# Current, the next subview (FORWARDS 1: FV's Next, the view behind; 0: FV's
# Prev, the view in front; a ring) that is visible, not disabled and
# selectable; '' when there is none other than Current, or no Current
fv.views._findNext() {
    local -n __fvw_nd=${1}_data __fvw_nl=${1}_views
    local __fvw_c=${__fvw_nd[Current]-} __fvw_i=-1 __fvw_j __fvw_m=${#__fvw_nl[@]} __fvw_k
    __fvw_n=''
    if [[ -z $__fvw_c ]]; then return 0; fi
    fv.views._idx "$1" "$__fvw_c"
    if (( __fvw_i < 0 )); then return 0; fi
    __fvw_j=$__fvw_i
    while :; do
        if (( $2 )); then __fvw_j=$(( (__fvw_j - 1 + __fvw_m) % __fvw_m )); else __fvw_j=$(( (__fvw_j + 1) % __fvw_m )); fi
        if (( __fvw_j == __fvw_i )); then return 0; fi
        __fvw_k=${__fvw_nl[__fvw_j]}
        local -n __fvw_nk=${__fvw_k}_data
        if (( (${__fvw_nk[State]:-0} & (FV_SF_VISIBLE | FV_SF_DISABLED)) == FV_SF_VISIBLE && (${__fvw_nk[Options]:-0} & FV_OF_SELECTABLE) )); then
            __fvw_n=$__fvw_k
            return 0
        fi
    done
}

# fv.views.focusNext G FORWARDS — FV FocusNext(Forwards): rc of the focus on
# the next selectable subview (FORWARDS 1 / 0 as fv.views._findNext); rc 0
# when there is none. selectNext G FORWARDS — FV SelectNext: that view
# selected. TWindow's kbTab is focusNext W 0, kbShiftTab focusNext W 1.
# RESULT is kept
fv.views.focusNext() { fv.views._next "$@" focusNext; }
fv.views.selectNext() { fv.views._next "$@" selectNext; }
fv.views._next() {   # G FORWARDS CALLER
    if (( $# != 3 )); then fv.views._bad "${!#}" 'wrong argument count'; return; fi
    fv.views._group "$1" "$3" || return
    if ! [[ $2 == [01] ]]; then fv.views._bad "$3" 'FORWARDS must be 1 or 0'; return; fi
    local __fvw_n __fvw_rr=${RESULT-} __fvw_s=0
    fv.views._findNext "$1" "$2"
    if [[ -n $__fvw_n ]]; then
        if [ "$3" = focusNext ]; then fv.views._focus "$__fvw_n" || __fvw_s=$?; else fv.views._select "$__fvw_n"; fi
    fi
    RESULT=$__fvw_rr
    return "$__fvw_s"
}

# ---- commands (FV command sets; design §1.8) -------------------------------------
# Commands are names (cmClose, cmMyThing: letters, digits, _). The set kept
# is the DISABLED one (__FV_VW_CMDOFF): FV's CurCommandSet — [0..255] minus
# cmZoom cmClose cmResize cmNext cmPrev at the start — is its complement, so
# a name never disabled is enabled (as FV's commands above 255 always are).
# A change sets FV_COMMANDSETCHANGED=1 (FV CommandSetChanged; fv.app's Idle
# broadcasts cmCommandSetChanged and clears it).

# fv.views._cmdNames CALLER NAME... — rc 0 when every NAME is a command name;
# else fv.views._bad's rc 2
fv.views._cmdNames() {
    local __fvw_c=$1 __fvw_n
    shift
    for __fvw_n; do
        if [[ -z $__fvw_n || $__fvw_n == *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]* ]]; then
            fv.views._bad "$__fvw_c" "'$__fvw_n' is not a command name (letters, digits, _)"; return
        fi
    done
}
# fv.views._cmds OFF NAME... — disable (OFF 1) / enable (0) the names
fv.views._cmds() {
    local __fvw_o=$1 __fvw_n
    shift
    for __fvw_n; do
        if (( __fvw_o )); then
            if [[ -z ${__FV_VW_CMDOFF[$__fvw_n]-} ]]; then __FV_VW_CMDOFF[$__fvw_n]=1 FV_COMMANDSETCHANGED=1; fi
        elif [[ -n ${__FV_VW_CMDOFF[$__fvw_n]-} ]]; then
            unset '__FV_VW_CMDOFF[$__fvw_n]'
            FV_COMMANDSETCHANGED=1
        fi
    done
}

# fv.views.enableCommands CMD... / disableCommands CMD... — FV
# EnableCommands / DisableCommands
fv.views.enableCommands() {
    fv.views._cmdNames enableCommands "$@" || return
    fv.views._cmds 0 "$@"
}
fv.views.disableCommands() {
    fv.views._cmdNames disableCommands "$@" || return
    fv.views._cmds 1 "$@"
}
# fv.views.commandEnabled CMD — FV CommandEnabled: rc 0 when CMD is enabled
fv.views.commandEnabled() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._cmdNames commandEnabled "$1" || return
    [[ -z ${__FV_VW_CMDOFF[$1]-} ]]
}
# fv.views.getCommands — RESULT = the DISABLED commands, sorted (C order),
# space-separated (FV GetCommands answers the enabled set; with names that
# set has no end). setCommands [CMD...] — exactly these disabled (FV
# SetCommands with the complement): the pair saves and restores a set
fv.views.getCommands() {
    if (( $# )); then fv.views._bad "${FUNCNAME#fv.views.}" 'no arguments'; return; fi
    local LC_ALL=C
    local -a __fvw_a=()
    local __fvw_n __fvw_i
    for __fvw_n in "${!__FV_VW_CMDOFF[@]}"; do
        for (( __fvw_i = 0; __fvw_i < ${#__fvw_a[@]}; __fvw_i++ )); do
            if [[ $__fvw_n < ${__fvw_a[__fvw_i]} ]]; then break; fi
        done
        __fvw_a=("${__fvw_a[@]:0:__fvw_i}" "$__fvw_n" "${__fvw_a[@]:__fvw_i}")
    done
    local IFS=' '
    RESULT="${__fvw_a[*]}"
}
fv.views.setCommands() {
    fv.views._cmdNames setCommands "$@" || return
    local -A __fvw_w=()
    local __fvw_n
    for __fvw_n; do __fvw_w[$__fvw_n]=1; done
    for __fvw_n in "${!__FV_VW_CMDOFF[@]}"; do
        if [[ -z ${__fvw_w[$__fvw_n]-} ]]; then fv.views._cmds 0 "$__fvw_n"; fi
    done
    fv.views._cmds 1 "$@"
}

# ---- the cursor (FV ResetCursor, SetCursor, Show / Hide / Block / NormalCursor) --

# fv.views.resetCursor V — FV ResetCursor for V's tree: the focused leaf
# (from the root, while the root has sfFocused: Current after Current as
# long as it has sfFocused) shows the hardware cursor at its CursorX /
# CursorY when it has sfVisible + sfCursorVis + sfFocused, the cell lies
# inside it and inside every owner (its clip), no visible view in front of
# it or of an owner holds the cell, and every owner is visible: underline,
# block with sfCursorIns (FV crUnderline / crBlock, fv.video.setCursorType 1
# / 2). Otherwise the cursor is hidden (type 0). When the cursor changed the
# terminal is updated (unless held). The modal loop calls it after each
# event; setState calls it on sfFocused / sfCursorVis / sfCursorIns.
# RESULT is kept
fv.views.resetCursor() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" resetCursor || return
    fv.views._resetCursor "$1"
}
fv.views._resetCursor() {
    local __fvw_v=$1 __fvw_x=0 __fvw_y=0 __fvw_t=0 __fvw_o __fvw_i __fvw_k __fvw_j __fvw_n __fvw_c=0 __fvw_rr=${RESULT-}
    local __fvw_m=$(( FV_SF_VISIBLE | FV_SF_CURSORVIS | FV_SF_FOCUSED )) __fvw_g=0
    # (each walk bounded: a cycle in the Owner / Current chain - a tree made
    # wrong by hand - must not hang the event loop)
    while (( __fvw_g++ < 4096 )); do
        local -n __fvw_cd=${__fvw_v}_data
        __fvw_o=${__fvw_cd[Owner]-}
        if [[ -z $__fvw_o ]]; then break; fi
        __fvw_v=$__fvw_o
    done
    __fvw_g=0
    if (( ${__fvw_cd[State]:-0} & FV_SF_FOCUSED )); then
        while [[ -n ${__FV_VW_GRP[$__fvw_v]-} ]] && (( __fvw_g++ < 4096 )); do
            __fvw_k=${__fvw_cd[Current]-}
            if [[ -z $__fvw_k || -z ${__FV_VW_LIVE[$__fvw_k]-} ]]; then break; fi
            local -n __fvw_ck=${__fvw_k}_data
            if (( ! (${__fvw_ck[State]:-0} & FV_SF_FOCUSED) )); then break; fi
            __fvw_v=$__fvw_k
            local -n __fvw_cd=${__fvw_v}_data
        done
        if (( (${__fvw_cd[State]:-0} & __fvw_m) == __fvw_m )); then fv.views._cursorAt; fi
    fi
    # (fv.video's cursor state read as a friend: __FV_VS_CURX / _CURY / _CURT)
    if (( __fvw_t )); then
        if (( __fvw_x != ${__FV_VS_CURX:-0} || __fvw_y != ${__FV_VS_CURY:-0} || __fvw_t != ${__FV_VS_CURT:-0} )); then
            fv.video.setCursorPos "$__fvw_x" "$__fvw_y" || :
            fv.video.setCursorType "$__fvw_t" || :
            __fvw_c=1
        fi
    elif (( ${__FV_VS_CURT:-0} != 0 )); then
        fv.video.setCursorType 0 || :
        __fvw_c=1
    fi
    if (( __fvw_c )); then fv.views._flush; fi
    RESULT=$__fvw_rr
}

# fv.views._cursorAt — _resetCursor's visible cursor (its locals: __fvw_v
# the focused view, its data __fvw_cd): __fvw_x / __fvw_y its place, __fvw_t
# its type, 0 when the place is outside the view's clip or a visible view in
# front of it (or of an owner) holds it, or an owner is hidden. Apart because
# bash copies a function's body on every call (most events have no cursor)
fv.views._cursorAt() {
    __fvw_x=$(( __FV_VW_AX[$__fvw_v] + ${__fvw_cd[CursorX]:-0} )) __fvw_y=$(( __FV_VW_AY[$__fvw_v] + ${__fvw_cd[CursorY]:-0} ))
    if (( __fvw_x >= 0 && __fvw_y >= 0 && __fvw_x >= __FV_VW_C1[$__fvw_v] && __fvw_x < __FV_VW_C3[$__fvw_v] )) \
       && (( __fvw_y >= __FV_VW_C2[$__fvw_v] && __fvw_y < __FV_VW_C4[$__fvw_v] )); then
        __fvw_t=1
        if (( ${__fvw_cd[State]:-0} & FV_SF_CURSORINS )); then __fvw_t=2; fi
        # covered by a visible view in front of it or of an owner, or an owner hidden
        __fvw_k=$__fvw_v __fvw_g=0
        while (( __fvw_t && __fvw_g++ < 4096 )); do
            local -n __fvw_cu=${__fvw_k}_data
            __fvw_o=${__fvw_cu[Owner]-}
            if [[ -z $__fvw_o ]]; then break; fi
            local -n __fvw_co=${__fvw_o}_data __fvw_cl=${__fvw_o}_views
            if (( ! (${__fvw_co[State]:-0} & FV_SF_VISIBLE) )); then __fvw_t=0; break; fi
            __fvw_i=-1
            fv.views._idx "$__fvw_o" "$__fvw_k"
            __fvw_n=${#__fvw_cl[@]}
            for (( __fvw_i = __fvw_i + 1; __fvw_i < __fvw_n; __fvw_i++ )); do
                __fvw_j=${__fvw_cl[__fvw_i]}
                local -n __fvw_cj=${__fvw_j}_data
                if (( (${__fvw_cj[State]:-0} & FV_SF_VISIBLE) && __fvw_x >= __FV_VW_AX[$__fvw_j] && __fvw_y >= __FV_VW_AY[$__fvw_j] )) \
                   && (( __fvw_x < __FV_VW_AX[$__fvw_j] + ${__fvw_cj[SizeX]:-0} && __fvw_y < __FV_VW_AY[$__fvw_j] + ${__fvw_cj[SizeY]:-0} )); then
                    __fvw_t=0
                    break
                fi
            done
            __fvw_k=$__fvw_o
        done
    fi
}

# fv.views.setCursor V X Y — FV SetCursor: V's CursorX / CursorY, then the
# cursor (resetCursor) when V is focused. RESULT is kept
fv.views.setCursor() {
    if (( $# != 3 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" setCursor || return
    local -a __fvw_v
    if ! fv.views._ints "$2" "$3"; then fv.views._bad setCursor 'X Y must be integers'; return; fi
    local -n __fvw_d=${1}_data
    __fvw_d[CursorX]=${__fvw_v[0]} __fvw_d[CursorY]=${__fvw_v[1]}
    if (( ${__fvw_d[State]:-0} & FV_SF_FOCUSED )); then fv.views._resetCursor "$1"; fi
    return 0
}
# fv.views.showCursor V / hideCursor V / blockCursor V / normalCursor V — FV
# ShowCursor / HideCursor (SetState sfCursorVis) and BlockCursor /
# NormalCursor (SetState sfCursorIns), through the elision
fv.views.showCursor() { fv.views._curState "$#" "${1-}" "$FV_SF_CURSORVIS" 1 showCursor; }
fv.views.hideCursor() { fv.views._curState "$#" "${1-}" "$FV_SF_CURSORVIS" 0 hideCursor; }
fv.views.blockCursor() { fv.views._curState "$#" "${1-}" "$FV_SF_CURSORINS" 1 blockCursor; }
fv.views.normalCursor() { fv.views._curState "$#" "${1-}" "$FV_SF_CURSORINS" 0 normalCursor; }
fv.views._curState() {   # ARGC V BIT ENABLE CALLER
    if (( $1 != 1 )); then fv.views._bad "$5" 'wrong argument count'; return; fi
    fv.views._view "$2" "$5" || return
    fv.views._virt "$2" SetState "$3" "$4" || :
    return 0
}

# ---- modal views (FV Execute, ExecView, EndModal, Valid, MouseEvent; design §2.2) --

# fv.views._ownerOk CALLER — rc 0 in the process that owns the screen
# (__FV_VW_OWNER); else fv.views._bad's rc 2: a modal loop inside $( ) or
# a pipeline would draw through the parent's screen while the parent's
# buffer and shown copy go stale
fv.views._ownerOk() {
    if [ "$BASHPID" = "$__FV_VW_OWNER" ]; then return 0; fi
    fv.views._bad "$1" "refused in a subshell (BASHPID $BASHPID; the screen belongs to $__FV_VW_OWNER): run the modal loop in the shell that owns the screen"
}

# TView.Execute (func) — FV: cmCancel
fv.views._viewExecute() { RESULT=cmCancel; }

# TGroup.Execute (func) — FV's modal loop: EndState := ''; read an event
# from __FV_VW_GETEVENT and hand it to G's HandleEvent (through the
# elision), then resetCursor, until EndState is set (fv.views.endModal);
# repeat while G's Valid(EndState) says no. RESULT = EndState, which is
# cleared. Deviation (design §2.1): no HandleEvent for evNothing (periodic
# work belongs in fv.app's Idle). The END OF INPUT (the event source's rc 1;
# any other non-zero rc is taken for it too, with a debug line: a broken
# source must not spin) latches __FV_VW_EOF: this loop and every running one
# end after the current event WITHOUT asking Valid, with cmCancel (cmQuit
# for a G without an owner: the application). rc 2 in a subshell
# (fv.views._ownerOk). A G destroyed by its own handler: cmCancel
fv.views._groupExecute() {
    fv.views._ownerOk Execute || return
    local -n __fvw_xd=${1}_data
    local __fvw_q=cmCancel __fvw_rt=$1 __fvw_s __fvw_e='' __fvw_z=0 __fvw_g=0
    if [[ -z ${__fvw_xd[Owner]-} ]]; then __fvw_q=cmQuit; fi
    while (( __fvw_g++ < 4096 )); do
        local -n __fvw_xr=${__fvw_rt}_data
        if [[ -z ${__fvw_xr[Owner]-} ]]; then break; fi
        __fvw_rt=${__fvw_xr[Owner]}
    done
    while :; do
        __fvw_xd[EndState]=''
        while :; do
            if (( __FV_VW_EOF )); then __fvw_z=1; break 2; fi
            __fvw_s=0
            "$__FV_VW_GETEVENT" || __fvw_s=$?
            if (( __fvw_s )); then
                if (( __fvw_s != 1 )); then kk.debug "Error: fv.views.Execute: the event source '$__FV_VW_GETEVENT' failed (rc $__fvw_s): taken for the end of input"; fi
                __FV_VW_EOF=1 __fvw_z=1
                break 2
            fi
            # (a source that leaves FV_EV_WHAT empty: evNothing)
            if [[ -z $FV_EV_WHAT ]]; then FV_EV_WHAT=evNothing; fi
            if ! [ "$FV_EV_WHAT" = evNothing ]; then
                # (one terminal update per event: the drawing entries of the
                # handler hold theirs; fv.views._showNow sends it at the end)
                __FV_VW_LSU=$(( __FV_VW_LSU + 1 )) __FV_VW_EH=$(( __FV_VW_EH + 1 ))
                fv.views._virt "$1" HandleEvent || :
                __FV_VW_CPEND=''
                if [[ -n ${__FV_VW_LIVE[$__fvw_rt]-} ]]; then fv.views._resetCursor "$__fvw_rt"; fi
                __FV_VW_LSU=$(( __FV_VW_LSU - 1 )) __FV_VW_EH=$(( __FV_VW_EH - 1 ))
                if (( __FV_VW_LSU < 0 )); then __FV_VW_LSU=0; fi
                if (( __FV_VW_EH < 0 )); then __FV_VW_EH=0; fi
                fv.views._showNow
                if [[ -z ${__FV_VW_LIVE[$1]-} ]]; then RESULT=cmCancel; return 0; fi
            fi
            if [[ -n ${__fvw_xd[EndState]-} ]]; then break; fi
        done
        if (( __FV_VW_EOF )); then __fvw_z=1; break; fi
        __fvw_e=${__fvw_xd[EndState]}
        if fv.views._virt "$1" Valid "$__fvw_e"; then break; fi
        if [[ -z ${__FV_VW_LIVE[$1]-} ]]; then RESULT=cmCancel; return 0; fi
    done
    if (( __fvw_z )); then __fvw_e=$__fvw_q; fi
    __fvw_xd[EndState]=''
    RESULT=$__fvw_e
}

# fv.views.execView G P — FV ExecView: P runs modal inside G; RESULT = the
# command P's Execute answered (cmCancel when it failed). Saves the event
# record, G's Phase, P's Options and owner, the top view, G's Current and
# the command set; then P not selectable, sfModal, P G's Current
# (EnterSelect: the old Current stays selected), P inserted when it has no
# owner; P's Execute (through the elision); then G's Current back
# (LeaveSelect), P removed when it was inserted here, and everything put
# back — the event record too, so the caller's dispatch goes on with its own
# event. P '' (FV nil): cmCancel. After the end of input (the latch):
# cmCancel at once, no loop. rc 2: not a group / view, or in a subshell
# (fv.views._ownerOk, a debug line)
fv.views.execView() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" execView || return
    if [[ -z $2 ]]; then RESULT=cmCancel; return 0; fi
    fv.views._view "$2" execView || return
    local __fvw_u=$1 __fvw_n=0
    while [[ -n $__fvw_u ]] && (( __fvw_n++ < 4096 )); do
        if [ "$__fvw_u" = "$2" ]; then fv.views._bad execView "'$2' is '$1' or one of its owners"; return; fi
        local -n __fvw_ud=${__fvw_u}_data
        __fvw_u=${__fvw_ud[Owner]-}
    done
    fv.views._ownerOk execView || return
    if (( __FV_VW_EOF )); then RESULT=cmCancel; return 0; fi
    local -n __fvw_gd=${1}_data __fvw_pd=${2}_data
    local __fvw_so=${__fvw_pd[Options]:-0} __fvw_sw=${__fvw_pd[Owner]-} __fvw_st=$__FV_VW_TOPVIEW
    local __fvw_sc=${__fvw_gd[Current]-} __fvw_ph=${__fvw_gd[Phase]-} __fvw_r=cmCancel __fvw_sk
    local -a __fvw_es __fvw_cs=("${!__FV_VW_CMDOFF[@]}")
    fv.views._evSave
    __FV_VW_TOPVIEW=$2
    __fvw_pd[Options]=$(( __fvw_so & ~FV_OF_SELECTABLE ))
    fv.views._virt "$2" SetState "$FV_SF_MODAL" 1 || :
    fv.views._setCurrent "$1" "$2" enter
    if [[ -z $__fvw_sw ]]; then fv.views.insert "$1" "$2" || :; fi
    # (shown now, also inside a handler of an outer modal loop)
    fv.views._showNow
    RESULT=''
    if fv.views._virt "$2" Execute && [[ -n ${RESULT-} ]]; then __fvw_r=$RESULT; fi
    if [[ -n $__fvw_sc && -z ${__FV_VW_LIVE[$__fvw_sc]-} ]]; then __fvw_sc=''; fi
    if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then
        # (a P inserted here leaves: nothing of it is redrawn for its focus
        # change; a P that stays in G is redrawn as any deselected view)
        __fvw_sk=$__FV_VW_SKIP
        if [[ -z $__fvw_sw ]]; then __FV_VW_SKIP=$2; fi
        fv.views._setCurrent "$1" "$__fvw_sc" leave
        __FV_VW_SKIP=$__fvw_sk
    fi
    if [[ -n ${__FV_VW_LIVE[$2]-} ]]; then
        if [[ -z $__fvw_sw && -n ${__FV_VW_LIVE[$1]-} ]] && [ "${__fvw_pd[Owner]-}" = "$1" ]; then fv.views.delete "$1" "$2" || :; fi
        fv.views._virt "$2" SetState "$FV_SF_MODAL" 0 || :
        __fvw_pd[Options]=$__fvw_so
    fi
    __FV_VW_TOPVIEW=$__fvw_st
    fv.views.setCommands "${__fvw_cs[@]}"
    if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then __fvw_gd[Phase]=$__fvw_ph; fi
    fv.views._evRestore
    RESULT=$__fvw_r
}

# fv.views.topView V — FV TopView: RESULT = the view execView runs while it
# is live, else the first of V and its owners with sfModal; '' when none.
# rc 2 for a malformed call
fv.views.topView() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" topView || return
    local __fvw_t
    fv.views._topView "$1"
    RESULT=$__fvw_t
}
# fv.views._topView V — topView's work into the caller's __fvw_t (a friend
# entry: fv.menus' Update calls it on every idle tick without the checks)
fv.views._topView() {
    __fvw_t=''
    if [[ -n $__FV_VW_TOPVIEW && -n ${__FV_VW_LIVE[$__FV_VW_TOPVIEW]-} ]]; then __fvw_t=$__FV_VW_TOPVIEW; return 0; fi
    local __fvw_u=$1 __fvw_g=0
    while [[ -n $__fvw_u && -n ${__FV_VW_LIVE[$__fvw_u]-} ]] && (( __fvw_g++ < 4096 )); do
        local -n __fvw_ud=${__fvw_u}_data
        if (( ${__fvw_ud[State]:-0} & FV_SF_MODAL )); then __fvw_t=$__fvw_u; return 0; fi
        __fvw_u=${__fvw_ud[Owner]-}
    done
}

# fv.views.endModal V CMD — FV EndModal(Command) of V: the top view's
# EndModal (virtual; TGroup's sets its EndState when it is modal), so the
# loop that runs it ends with CMD (after its Valid). rc 1 when no view is
# modal. RESULT is kept
fv.views.endModal() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" endModal || return
    fv.views._cmdNames endModal "$2" || return
    local __fvw_t
    fv.views._topView "$1"
    if [[ -z $__fvw_t ]]; then RESULT=''; kk.debug "Error: fv.views.endModal: no modal view above '$1'"; return 1; fi
    fv.views._virt "$__fvw_t" EndModal "$2" || :
    return 0
}
# TView.EndModal CMD — FV: the top view's EndModal (none or V itself: nothing)
fv.views._viewEndModal() {
    local __fvw_t
    fv.views._topView "$1"
    if [[ -n $__fvw_t ]] && ! [ "$__fvw_t" = "$1" ]; then fv.views._virt "$__fvw_t" EndModal "$2" || :; fi
    return 0
}
# TGroup.EndModal CMD — FV: a modal G takes CMD as its EndState; else TView's
fv.views._groupEndModal() {
    local -n __fvw_md=${1}_data
    if (( ${__fvw_md[State]:-0} & FV_SF_MODAL )); then __fvw_md[EndState]=$2; else fv.views._viewEndModal "$@"; fi
    return 0
}

# TView.Valid CMD (func) — FV: true. The answer of Valid is its rc: 0 =
# valid (RESULT 1), non-zero = not valid. An override says no with an
# explicit `return 1` or a failing last command (kklass round 7, K-2: a func
# fails with its body's rc; before it, a failing last command answered rc 0)
fv.views._viewValid() { RESULT=1; }
# TGroup.Valid CMD (func) — FV: for cmReleasedFocus only Current's Valid,
# and only when Current has ofValidate; for any other command every
# subview's Valid (front to back; the first "no" answers rc 1)
fv.views._groupValid() {
    local -n __fvw_vl=${1}_views __fvw_vd=${1}_data
    local __fvw_k __fvw_i
    if [ "${2-}" = cmReleasedFocus ]; then
        __fvw_k=${__fvw_vd[Current]-}
        if [[ -n $__fvw_k && -n ${__FV_VW_LIVE[$__fvw_k]-} ]]; then
            local -n __fvw_vk=${__fvw_k}_data
            if (( ${__fvw_vk[Options]:-0} & FV_OF_VALIDATE )); then fv.views._virt "$__fvw_k" Valid "$2" || return 1; fi
        fi
    else
        local -a __fvw_ks=("${__fvw_vl[@]}")
        for (( __fvw_i = ${#__fvw_ks[@]} - 1; __fvw_i >= 0; __fvw_i-- )); do
            __fvw_k=${__fvw_ks[__fvw_i]}
            if [[ -z ${__FV_VW_LIVE[$__fvw_k]-} ]]; then continue; fi
            fv.views._virt "$__fvw_k" Valid "${2-}" || return 1
        done
    fi
    RESULT=1
}

# fv.views.mouseEvent V MASK — FV MouseEvent(Event, Mask): read events from
# __FV_VW_GETEVENT, dropping the others, until one whose bit is in MASK
# (FV_EM_* bits) or a mouse-up; that event stays in FV_EV_* (FV's var
# parameter: the caller tracks a drag with it). rc 0 for a MASK event, 1 for
# the mouse-up, and 1 at the end of input (latched; FV_EV_WHAT=evNothing):
# the tracking loop ends instead of spinning. RESULT is kept
fv.views.mouseEvent() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" mouseEvent || return
    if [[ -z $2 || $2 == *[!0123456789]* || ${#2} -gt 9 ]]; then fv.views._bad mouseEvent 'MASK must be a number (FV_EM_* bits)'; return; fi
    local __fvw_m=$(( 10#$2 | FV_EM_MOUSEUP )) __fvw_s __fvw_rr=${RESULT-}
    while :; do
        # (what the handler drew so far is shown before the next event)
        fv.views._showNow
        if (( __FV_VW_EOF )); then FV_EV_WHAT=evNothing; RESULT=$__fvw_rr; return 1; fi
        __fvw_s=0
        "$__FV_VW_GETEVENT" || __fvw_s=$?
        if (( __fvw_s )); then
            if (( __fvw_s != 1 )); then kk.debug "Error: fv.views.mouseEvent: the event source '$__FV_VW_GETEVENT' failed (rc $__fvw_s): taken for the end of input"; fi
            __FV_VW_EOF=1
            FV_EV_WHAT=evNothing
            RESULT=$__fvw_rr
            return 1
        fi
        if [[ -z $FV_EV_WHAT ]]; then FV_EV_WHAT=evNothing; fi
        if (( ${__FV_VW_EVBIT[$FV_EV_WHAT]-0} & __fvw_m )); then break; fi
    done
    RESULT=$__fvw_rr
    if [ "$FV_EV_WHAT" = evMouseUp ]; then return 1; fi
    return 0
}

# ---- TWindow (FV views.inc TWindow: Init, InitFrame, GetPalette, GetTitle,
# SetState, HandleEvent, Close) ------------------------------------------------------

fv.views._windowCreate() {   # W TITLE NUMBER
    local -n __fvw_wd=${1}_data
    local __fvw_f
    local -a __fvw_v
    __fvw_wd[State]=$(( ${__fvw_wd[State]:-0} | FV_SF_SHADOW ))
    __fvw_wd[Options]=$(( ${__fvw_wd[Options]:-0} | FV_OF_SELECTABLE | FV_OF_TOPSELECT ))
    __fvw_wd[GrowMode]=$(( FV_GF_GROWALL | FV_GF_GROWREL ))
    __fvw_wd[Flags]=$(( FV_WF_MOVE | FV_WF_GROW | FV_WF_CLOSE | FV_WF_ZOOM ))
    __fvw_wd[Title]=$2
    if fv.views._ints "${3:-0}"; then __fvw_wd[Number]=${__fvw_v[0]}; else __fvw_wd[Number]=$FV_WN_NONUMBER; fi
    __fvw_wd[Palette]=$FV_WP_BLUEWINDOW __fvw_wd[Frame]=''
    fv.views._virt "$1" InitFrame || :
    __fvw_f=${__fvw_wd[Frame]-}
    if [[ -n $__fvw_f && -n ${__FV_VW_LIVE[$__fvw_f]-} ]]; then fv.views.insert "$1" "$__fvw_f" || :; fi
    __fvw_wd[ZoomRect]="${__fvw_wd[OriginX]:-0} ${__fvw_wd[OriginY]:-0} $(( ${__fvw_wd[OriginX]:-0} + ${__fvw_wd[SizeX]:-0} )) $(( ${__fvw_wd[OriginY]:-0} + ${__fvw_wd[SizeY]:-0} ))"
}

# TWindow.InitFrame — FV: Frame := a TFrame over the window's extent, with
# the reserved name W__fvframe (TWindow's constructor inserts it). An
# override that leaves Frame '' makes a frameless window
fv.views._windowInitFrame() {
    local -n __fvw_wd=${1}_data
    if fv.views._newReserved "$1" frame TFrame 0 0 "${__fvw_wd[SizeX]:-0}" "${__fvw_wd[SizeY]:-0}"; then __fvw_wd[Frame]=$RESULT; fi
    return 0
}

# TWindow.GetPalette (func) — FV CBlueWindow / CCyanWindow / CGrayWindow by
# Palette (wpBlueWindow 0, wpCyanWindow 1, wpGrayWindow 2): CAppColor 8-15,
# 16-23, 24-31. After changing Palette: fv.views.resetPalette W and a redraw
fv.views._windowGetPalette() {
    local -n __fvw_wd=${1}_data
    case ${__fvw_wd[Palette]:-0} in
        1) RESULT='16 17 18 19 20 21 22 23' ;;
        2) RESULT='24 25 26 27 28 29 30 31' ;;
        *) RESULT='8 9 10 11 12 13 14 15' ;;
    esac
}

# TWindow.GetTitle MAXSIZE (func) — FV: Title, cut to MAXSIZE characters
fv.views._windowGetTitle() {
    local -n __fvw_wd=${1}_data
    local __fvw_t=${__fvw_wd[Title]-} __fvw_m=${2-}
    if [[ -n $__fvw_m && $__fvw_m != *[!0123456789]* && ${#__fvw_m} -le 9 ]] && (( ${#__fvw_t} > 10#$__fvw_m )); then
        __fvw_t=${__fvw_t:0:10#$__fvw_m}
    fi
    RESULT=$__fvw_t
}

# TWindow.SetState BIT ENABLE — FV: TGroup's; sfSelected -> SetState(sfActive)
# (virtual: the frame's border changes look); sfSelected, or sfExposed while
# selected -> the window commands enabled / disabled: cmNext cmPrev, cmResize
# (wfGrow or wfMove), cmClose (wfClose), cmZoom (wfZoom)
fv.views._windowSetState() {
    fv.views._groupSetState "$@"
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    if (( $2 == FV_SF_SELECTED )); then fv.views._virt "$1" SetState "$FV_SF_ACTIVE" "$3" || :; fi
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    if (( $2 == FV_SF_SELECTED || $2 == FV_SF_EXPOSED )); then fv.views._windowCmds "$1" "$2" "$3"; fi
    return 0
}
# fv.views._windowCmds W BIT ENABLE — TWindow.SetState's window commands:
# sfSelected, or sfExposed while selected -> cmNext cmPrev, cmResize (wfGrow
# or wfMove), cmClose (wfClose), cmZoom (wfZoom) enabled / disabled
fv.views._windowCmds() {
    local -n __fvw_wd=${1}_data
    if (( $2 == FV_SF_SELECTED || ($2 == FV_SF_EXPOSED && (${__fvw_wd[State]:-0} & FV_SF_SELECTED)) )); then
        local __fvw_f=${__fvw_wd[Flags]:-0}
        local -a __fvw_c=(cmNext cmPrev)
        if [[ $__fvw_f == *[!0123456789]* || ${#__fvw_f} -gt 9 ]]; then __fvw_f=0; else __fvw_f=$(( 10#$__fvw_f )); fi
        if (( __fvw_f & (FV_WF_GROW | FV_WF_MOVE) )); then __fvw_c+=(cmResize); fi
        if (( __fvw_f & FV_WF_CLOSE )); then __fvw_c+=(cmClose); fi
        if (( __fvw_f & FV_WF_ZOOM )); then __fvw_c+=(cmZoom); fi
        if (( $3 )); then fv.views._cmds 0 "${__fvw_c[@]}"; else fv.views._cmds 1 "${__fvw_c[@]}"; fi
    fi
    return 0
}

# TWindow.HandleEvent — FV: TGroup's, then:
#   * evCommand cmClose for this window (FV_EV_INFO '' or W) with wfClose:
#     handled; not modal -> Close (virtual: Valid(cmClose), then W.delete);
#     modal -> cmCancel posted (__FV_VW_PUTEVENT, FV PutEvent);
#   * evBroadcast cmSelectWindowNum with FV_EV_INFO = Number on a visible,
#     selectable window: select W, handled (a hidden window does not answer);
#   * evKeyDown kbTab, kbDown, kbRight -> focusNext W 0 (FV FocusNext(False):
#     the next control); kbShiftTab, kbUp, kbLeft -> focusNext W 1; handled.
#     (FPC's TWindow takes the arrows too: a control that uses them handles
#     them first, in the focused phase.)
#   * evCommand cmZoom for this window (FV_EV_INFO '' or W) with wfZoom: Zoom
#     (virtual), handled;
#   * evCommand cmResize with wfMove or wfGrow and an owner: the keyboard
#     drag (fv.views._dragWindow with Flags' move / grow bits, FV DragView),
#     handled.
fv.views._windowEvent() {
    fv.views._groupEvent "$1"
    if [ "$FV_EV_WHAT" = evNothing ] || [[ -z ${__FV_VW_LIVE[$1]-} ]]; then return 0; fi
    if [ "$FV_EV_WHAT" = evKeyDown ]; then
        if [ "$FV_EV_KEY" = kbTab ] || [ "$FV_EV_KEY" = kbDown ] || [ "$FV_EV_KEY" = kbRight ]; then
            fv.views._findFocus "$1" 0
            FV_EV_WHAT=evNothing FV_EV_INFO=$1
        elif [ "$FV_EV_KEY" = kbShiftTab ] || [ "$FV_EV_KEY" = kbUp ] || [ "$FV_EV_KEY" = kbLeft ]; then
            fv.views._findFocus "$1" 1
            FV_EV_WHAT=evNothing FV_EV_INFO=$1
        fi
    elif { [ "$FV_EV_WHAT" = evCommand ] && { [ "$FV_EV_COMMAND" = cmClose ] || [ "$FV_EV_COMMAND" = cmZoom ] || [ "$FV_EV_COMMAND" = cmResize ]; }; } \
         || { [ "$FV_EV_WHAT" = evBroadcast ] && [ "$FV_EV_COMMAND" = cmSelectWindowNum ]; }; then
        fv.views._windowEventX "$1"
    fi
    return 0
}
# fv.views._windowEventX W — TWindow.HandleEvent's commands (cmClose, cmZoom,
# cmResize) and cmSelectWindowNum (apart: bash copies a function's body on
# every call)
fv.views._windowEventX() {
    local -n __fvw_wd=${1}_data
    if [ "$FV_EV_WHAT" = evCommand ]; then
        if [ "$FV_EV_COMMAND" = cmClose ]; then
            if (( ${__fvw_wd[Flags]:-0} & FV_WF_CLOSE )) && { [[ -z $FV_EV_INFO ]] || [ "$FV_EV_INFO" = "$1" ]; }; then
                FV_EV_WHAT=evNothing FV_EV_INFO=$1
                if (( ! (${__fvw_wd[State]:-0} & FV_SF_MODAL) )); then
                    fv.views._virt "$1" Close || :
                else
                    FV_EV_WHAT=evCommand FV_EV_COMMAND=cmCancel
                    "$__FV_VW_PUTEVENT" || :
                    FV_EV_WHAT=evNothing FV_EV_INFO=$1
                fi
            fi
        elif [ "$FV_EV_COMMAND" = cmZoom ]; then
            if (( ${__fvw_wd[Flags]:-0} & FV_WF_ZOOM )) && { [[ -z $FV_EV_INFO ]] || [ "$FV_EV_INFO" = "$1" ]; }; then
                fv.views._virt "$1" Zoom || :
                FV_EV_WHAT=evNothing FV_EV_INFO=$1
            fi
        elif [ "$FV_EV_COMMAND" = cmResize ]; then
            if (( ${__fvw_wd[Flags]:-0} & (FV_WF_MOVE | FV_WF_GROW) )) && [[ -n ${__fvw_wd[Owner]-} ]]; then
                # (wfMove / wfGrow are dmDragMove / dmDragGrow: FV passes Flags' bits as the mode)
                fv.views._dragWindow "$1" "$(( ${__fvw_wd[Flags]:-0} & (FV_WF_MOVE | FV_WF_GROW) ))" || :
                FV_EV_WHAT=evNothing FV_EV_INFO=$1
            fi
        fi
    elif [ "$FV_EV_WHAT" = evBroadcast ]; then
        if [ "$FV_EV_COMMAND" = cmSelectWindowNum ] && [[ -n $FV_EV_INFO ]] && [ "$FV_EV_INFO" = "${__fvw_wd[Number]-}" ] \
           && (( (${__fvw_wd[Options]:-0} & FV_OF_SELECTABLE) && (${__fvw_wd[State]:-0} & FV_SF_VISIBLE) )); then
            fv.views._select "$1"
            FV_EV_WHAT=evNothing FV_EV_INFO=$1
        fi
    fi
    return 0
}
# fv.views._findFocus G FORWARDS — FocusNext without the argument checks
fv.views._findFocus() {
    local __fvw_n
    fv.views._findNext "$1" "$2"
    if [[ -n $__fvw_n ]]; then fv.views._focus "$__fvw_n" || :; fi
    return 0
}

# TWindow.Close — FV: when Valid(cmClose) agrees, the window is destroyed
# (FV Free: W.delete — out of its owner, the focus moves on, its area
# repainted)
fv.views._windowClose() {
    if fv.views._virt "$1" Valid cmClose; then
        if declare -F "$1.delete" >/dev/null; then "$1.delete"; fi
    fi
    return 0
}

# ==== zoom, dragging, the frame's mouse (P2 stage 2d; design §1.2, §1.3, §2.2) ====

# TWindow.SizeLimits — FV: TView's (the maximum: the owner's size), then the
# minimum = FV's MinWinSize (FV_MINWINSIZE_X / _Y; a value that is not 1-9
# plain digits counts as FV's 16 x 6)
fv.views._windowSizeLimits() {
    fv.views._viewSizeLimits "$1"
    FV_MIN_X=${FV_MINWINSIZE_X-} FV_MIN_Y=${FV_MINWINSIZE_Y-}
    if [[ -z $FV_MIN_X || $FV_MIN_X == *[!0123456789]* || ${#FV_MIN_X} -gt 9 ]]; then FV_MIN_X=16; else FV_MIN_X=$(( 10#$FV_MIN_X )); fi
    if [[ -z $FV_MIN_Y || $FV_MIN_Y == *[!0123456789]* || ${#FV_MIN_Y} -gt 9 ]]; then FV_MIN_Y=6; else FV_MIN_Y=$(( 10#$FV_MIN_Y )); fi
}

# fv.views._zoomRect W — the caller's __fvw_v = W's ZoomRect as four
# integers; rc 1 when the field is not "AX AY BX BY"
fv.views._zoomRect() {
    local -n __fvw_zd=${1}_data
    local __fvw_z="${__fvw_zd[ZoomRect]-} " __fvw_n=0
    local -a __fvw_p=()
    while [[ -n $__fvw_z ]] && (( __fvw_n++ < 5 )); do
        __fvw_p+=("${__fvw_z%% *}") __fvw_z=${__fvw_z#* }
    done
    if (( ${#__fvw_p[@]} != 4 )) || [[ -n $__fvw_z ]]; then return 1; fi
    fv.views._ints "${__fvw_p[@]}"
}

# TWindow.Zoom — FV: SizeLimits (virtual); smaller than its maximum: the
# bounds kept in ZoomRect, then Locate(0, 0, Max) (the owner's whole
# extent); at the maximum: Locate(ZoomRect). The frame's zoom icon follows
# (`↕` at the maximum: the frame's string cache key holds it). Nothing for a
# maximum that is not an integer of at most 9 digits (no owner: FV's
# high(Sw_Integer)) or a ZoomRect that is not four integers
fv.views._windowZoom() {
    local -n __fvw_wd=${1}_data
    local -a __fvw_v
    local __fvw_x=${__fvw_wd[OriginX]:-0} __fvw_y=${__fvw_wd[OriginY]:-0} __fvw_w=${__fvw_wd[SizeX]:-0} __fvw_h=${__fvw_wd[SizeY]:-0}
    fv.views._virt "$1" SizeLimits || :
    fv.views._ints "$FV_MAX_X" "$FV_MAX_Y" || return 0
    if (( __fvw_w != __fvw_v[0] || __fvw_h != __fvw_v[1] )); then
        __fvw_wd[ZoomRect]="$__fvw_x $__fvw_y $(( __fvw_x + __fvw_w )) $(( __fvw_y + __fvw_h ))"
        fv.views._locate "$1" 0 0 "${__fvw_v[0]}" "${__fvw_v[1]}" || :
    elif fv.views._zoomRect "$1"; then
        fv.views._locate "$1" "${__fvw_v[@]}" || :
    fi
    return 0
}

# TWindow.CalcBounds DX DY — FV (FPC 2026): the ZoomRect follows the owner's
# resize as the bounds do (TView's CalcBounds on the ZoomRect, the fields
# set to it meanwhile, then on the bounds); a ZoomRect that is not four
# integers is left alone. Answer: FV_RECT_* (the bounds)
fv.views._windowCalcBounds() {
    local -n __fvw_wd=${1}_data
    local -a __fvw_v
    if fv.views._zoomRect "$1"; then
        local __fvw_x=${__fvw_wd[OriginX]-} __fvw_y=${__fvw_wd[OriginY]-} __fvw_w=${__fvw_wd[SizeX]-} __fvw_h=${__fvw_wd[SizeY]-}
        __fvw_wd[OriginX]=${__fvw_v[0]} __fvw_wd[OriginY]=${__fvw_v[1]}
        __fvw_wd[SizeX]=$(( __fvw_v[2] - __fvw_v[0] )) __fvw_wd[SizeY]=$(( __fvw_v[3] - __fvw_v[1] ))
        fv.views._viewCalcBounds "$1" "$2" "$3"
        __fvw_wd[ZoomRect]="$FV_RECT_AX $FV_RECT_AY $FV_RECT_BX $FV_RECT_BY"
        __fvw_wd[OriginX]=$__fvw_x __fvw_wd[OriginY]=$__fvw_y __fvw_wd[SizeX]=$__fvw_w __fvw_wd[SizeY]=$__fvw_h
    fi
    fv.views._viewCalcBounds "$1" "$2" "$3"
}

# ---- dragging (FV TView.DragView) ---------------------------------------------------

# fv.views.dragView V MODE AX AY BX BY MINX MINY MAXX MAXY — FV DragView(Event,
# Mode, Limits, MinSize, MaxSize) with the event in FV_EV_*: a mouse-down
# drags by the mouse (dmDragMove in MODE: moves, else dmDragGrow: grows)
# until the mouse-up; anything else drags by the keyboard (the arrows move,
# Shift + arrows grow (dmDragMove / dmDragGrow), Ctrl+Left / Ctrl+Right by 8,
# Home / End / PgUp / PgDn to the limits' edges) until Enter (kept) or Esc
# (the start bounds back). The size stays within MIN..MAX, the origin keeps
# a column / row inside the limits (owner coordinates, B exclusive) and
# obeys MODE's dmLimit* bits; every step is a locate (old ∪ new redrawn
# once) shown at once. V has sfDragging meanwhile (a window's frame is
# redrawn border-only, D17). The end of input ends a keyboard drag as Esc,
# a mouse drag where it is; an evCommand cmResizeApp from the event source
# (which has handled the resize: fv.app) ends either at V's bounds clamped
# into its owner's new extent (no undo). Queued mouse moves are coalesced:
# before each step the waiting events are read with "$__FV_VW_GETEVENT" 0
# and the last move wins. The event record is put back afterwards; RESULT
# is kept. rc 2: a malformed call, or in a subshell (fv.views._ownerOk)
fv.views.dragView() {
    if (( $# != 10 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" dragView || return
    local -a __fvw_v
    local __fvw_a=${9} __fvw_b=${10}
    # (FV's high(Sw_Integer), TView.SizeLimits without an owner, as a maximum)
    if [ "$__fvw_a" = "$__FV_VW_HIGH" ]; then __fvw_a=999999999; fi
    if [ "$__fvw_b" = "$__FV_VW_HIGH" ]; then __fvw_b=999999999; fi
    if ! fv.views._ints "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$__fvw_a" "$__fvw_b"; then
        fv.views._bad dragView 'MODE, the limits and the sizes must be integers'; return
    fi
    fv.views._ownerOk dragView || return
    fv.views._drag "$1" "${__fvw_v[@]}"
}

# fv.views._dragWindow W MODE — FV's DragWindow (TWindow.HandleEvent's
# cmResize, TFrame.HandleEvent): W dragged with DragMode | MODE inside its
# owner's extent within its SizeLimits (virtual); the event in FV_EV_*.
# Nothing without an owner; rc 2 in a subshell
fv.views._dragWindow() {
    local -n __fvw_ww=${1}_data
    local __fvw_o=${__fvw_ww[Owner]-}
    if [[ -z $__fvw_o || -z ${__FV_VW_LIVE[$__fvw_o]-} ]]; then return 0; fi
    fv.views._ownerOk dragView || return
    local -n __fvw_wo=${__fvw_o}_data
    local __fvw_r=${RESULT-}
    fv.views._virt "$1" SizeLimits || :
    fv.views._drag "$1" "$(( ${__fvw_ww[DragMode]:-0} | $2 ))" 0 0 "${__fvw_wo[SizeX]:-0}" "${__fvw_wo[SizeY]:-0}" \
        "$FV_MIN_X" "$FV_MIN_Y" "$FV_MAX_X" "$FV_MAX_Y"
    RESULT=$__fvw_r
}

# fv.views._drag V MODE L1 L2 L3 L4 MINX MINY MAXX MAXY (integers) — DragView's
# frame: the event record saved, sfDragging on, the mouse or the keyboard
# loop, sfDragging off, the record put back
fv.views._drag() {
    local __fvw_m=$2 __fvw_l1=$3 __fvw_l2=$4 __fvw_l3=$5 __fvw_l4=$6 __fvw_n1=$7 __fvw_n2=$8 __fvw_x1=$9 __fvw_x2=${10}
    local __fvw_rr=${RESULT-}
    local -a __fvw_es
    fv.views._evSave
    fv.views._virt "$1" SetState "$FV_SF_DRAGGING" 1 || :
    if [ "$FV_EV_WHAT" = evMouseDown ]; then fv.views._dragMouse "$1"; else fv.views._dragKeys "$1"; fi
    if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then fv.views._virt "$1" SetState "$FV_SF_DRAGGING" 0 || :; fi
    fv.views._evRestore
    RESULT=$__fvw_rr
    return 0
}

# fv.views._moveGrow V PX PY SX SY — FV MoveGrow (the caller's __fvw_m mode,
# __fvw_l1..4 limits, __fvw_n1/2 minimum, __fvw_x1/2 maximum): S clamped to
# MIN..MAX, P to a column / row inside the limits, then the mode's dmLimit*
# bits; then locate (FV: Owner^.Lock around it, which redraws the owner; D17:
# locate redraws old ∪ new once)
fv.views._moveGrow() {
    local __fvw_px=$2 __fvw_py=$3 __fvw_sx=$4 __fvw_sy=$5
    if (( __fvw_sx < __fvw_n1 )); then __fvw_sx=$__fvw_n1; fi
    if (( __fvw_sx > __fvw_x1 )); then __fvw_sx=$__fvw_x1; fi
    if (( __fvw_sy < __fvw_n2 )); then __fvw_sy=$__fvw_n2; fi
    if (( __fvw_sy > __fvw_x2 )); then __fvw_sy=$__fvw_x2; fi
    if (( __fvw_px < __fvw_l1 - __fvw_sx + 1 )); then __fvw_px=$(( __fvw_l1 - __fvw_sx + 1 )); fi
    if (( __fvw_px > __fvw_l3 - 1 )); then __fvw_px=$(( __fvw_l3 - 1 )); fi
    if (( __fvw_py < __fvw_l2 - __fvw_sy + 1 )); then __fvw_py=$(( __fvw_l2 - __fvw_sy + 1 )); fi
    if (( __fvw_py > __fvw_l4 - 1 )); then __fvw_py=$(( __fvw_l4 - 1 )); fi
    if (( (__fvw_m & FV_DM_LIMITLOX) && __fvw_px < __fvw_l1 )); then __fvw_px=$__fvw_l1; fi
    if (( (__fvw_m & FV_DM_LIMITLOY) && __fvw_py < __fvw_l2 )); then __fvw_py=$__fvw_l2; fi
    if (( (__fvw_m & FV_DM_LIMITHIX) && __fvw_px > __fvw_l3 - __fvw_sx )); then __fvw_px=$(( __fvw_l3 - __fvw_sx )); fi
    if (( (__fvw_m & FV_DM_LIMITHIY) && __fvw_py > __fvw_l4 - __fvw_sy )); then __fvw_py=$(( __fvw_l4 - __fvw_sy )); fi
    fv.views._locate "$1" "$__fvw_px" "$__fvw_py" "$(( __fvw_px + __fvw_sx ))" "$(( __fvw_py + __fvw_sy ))" || :
}

# fv.views._dragNext KEYS — the next event a drag takes (FV KeyEvent, KEYS 1 /
# MouseEvent(evMouseMove), KEYS 0), what was drawn shown first; the others
# (evNothing included) are dropped. The caller's __fvw_e: k a key, m / u a
# mouse move / up, z an evCommand cmResizeApp, e the end of input (latched,
# as the modal loop does; a source failing otherwise counts as it, with a
# debug line)
fv.views._dragNext() {
    local __fvw_s __fvw_rz
    while :; do
        fv.views._showNow
        if (( __FV_VW_EOF )); then __fvw_e=e; return 0; fi
        __fvw_s=0 __fvw_rz=$__FV_VW_RESIZES
        "$__FV_VW_GETEVENT" || __fvw_s=$?
        if (( __fvw_s )); then
            if (( __fvw_s != 1 )); then kk.debug "Error: fv.views.dragView: the event source '$__FV_VW_GETEVENT' failed (rc $__fvw_s): taken for the end of input"; fi
            __FV_VW_EOF=1 __fvw_e=e
            return 0
        fi
        # (a resize the source handled itself: __FV_VW_RESIZES)
        if (( __FV_VW_RESIZES != __fvw_rz )); then __fvw_e=z; return 0; fi
        if [ "$FV_EV_WHAT" = evKeyDown ]; then
            if (( $1 )); then __fvw_e=k; return 0; fi
        elif [ "$FV_EV_WHAT" = evMouseMove ]; then
            if (( ! $1 )); then __fvw_e=m; return 0; fi
        elif [ "$FV_EV_WHAT" = evMouseUp ]; then
            if (( ! $1 )); then __fvw_e=u __fvw_ux=$FV_EV_MOUSE_X __fvw_uy=$FV_EV_MOUSE_Y; return 0; fi
        elif [ "$FV_EV_WHAT" = evCommand ] && [ "$FV_EV_COMMAND" = cmResizeApp ]; then
            __fvw_e=z
            return 0
        fi
    done
}

# fv.views._dragDrain — motion coalescing (design §2.2, R10): the events
# already waiting are read ("$__FV_VW_GETEVENT" 0: fv.drivers' "only what is
# there"); each mouse move replaces the caller's __fvw_mx / __fvw_my; the
# first evNothing stops, and so does an evMouseAuto (fv.drivers sends one
# instead of evNothing while a button is held: with a tiny FV_IDLE_TIMEOUT or
# a slow loop every read may give one, and the drain would never end); a
# mouse-up (its place in __fvw_ux / __fvw_uy), a cmResizeApp or the end of
# input stops and is kept for the loop (__fvw_pe = u / z / e); anything else
# is dropped (FV's MouseEvent drops it)
fv.views._dragDrain() {
    local __fvw_s __fvw_rz
    while :; do
        __fvw_s=0 __fvw_rz=$__FV_VW_RESIZES
        "$__FV_VW_GETEVENT" 0 || __fvw_s=$?
        if (( __fvw_s )); then
            if (( __fvw_s != 1 )); then kk.debug "Error: fv.views.dragView: the event source '$__FV_VW_GETEVENT' failed (rc $__fvw_s): taken for the end of input"; fi
            __FV_VW_EOF=1 __fvw_pe=e
            return 0
        fi
        if (( __FV_VW_RESIZES != __fvw_rz )); then __fvw_pe=z; return 0; fi
        if [ "$FV_EV_WHAT" = evMouseMove ]; then __fvw_mx=$FV_EV_MOUSE_X __fvw_my=$FV_EV_MOUSE_Y
        elif [ "$FV_EV_WHAT" = evMouseUp ]; then __fvw_pe=u __fvw_ux=$FV_EV_MOUSE_X __fvw_uy=$FV_EV_MOUSE_Y; return 0
        elif [ "$FV_EV_WHAT" = evCommand ] && [ "$FV_EV_COMMAND" = cmResizeApp ]; then __fvw_pe=z; return 0
        elif [[ -z $FV_EV_WHAT ]] || [ "$FV_EV_WHAT" = evNothing ] || [ "$FV_EV_WHAT" = evMouseAuto ]; then return 0; fi
    done
}

# fv.views._dragMouse V — DragView's mouse part (the caller's _drag locals):
# dmDragMove: the origin follows the mouse by the offset of the mouse-down;
# else the size does. The first step at the mouse-down's place (FV), one per
# (coalesced) move, the last at the mouse-up's place (FV: "not all terminals
# send drag events"); the end of input ends it where it is; a cmResizeApp:
# fv.views._dragResized
fv.views._dragMouse() {
    local -n __fvw_dm=${1}_data
    local __fvw_mx=$FV_EV_MOUSE_X __fvw_my=$FV_EV_MOUSE_Y __fvw_ox __fvw_oy __fvw_e='' __fvw_pe='' __fvw_ux=0 __fvw_uy=0 __fvw_mv=0
    if (( __fvw_m & FV_DM_DRAGMOVE )); then
        __fvw_mv=1 __fvw_ox=$(( ${__fvw_dm[OriginX]:-0} - __fvw_mx )) __fvw_oy=$(( ${__fvw_dm[OriginY]:-0} - __fvw_my ))
    else
        __fvw_ox=$(( ${__fvw_dm[SizeX]:-0} - __fvw_mx )) __fvw_oy=$(( ${__fvw_dm[SizeY]:-0} - __fvw_my ))
    fi
    while :; do
        [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
        if (( __fvw_mv )); then
            fv.views._moveGrow "$1" "$(( __fvw_mx + __fvw_ox ))" "$(( __fvw_my + __fvw_oy ))" "${__fvw_dm[SizeX]:-0}" "${__fvw_dm[SizeY]:-0}"
        else
            fv.views._moveGrow "$1" "${__fvw_dm[OriginX]:-0}" "${__fvw_dm[OriginY]:-0}" "$(( __fvw_mx + __fvw_ox ))" "$(( __fvw_my + __fvw_oy ))"
        fi
        if [ "$__fvw_e" = u ]; then return 0; fi
        if [[ -n $__fvw_pe ]]; then __fvw_e=$__fvw_pe __fvw_pe=''; else fv.views._dragNext 0; fi
        if [ "$__fvw_e" = m ]; then
            __fvw_mx=$FV_EV_MOUSE_X __fvw_my=$FV_EV_MOUSE_Y
            fv.views._dragDrain
        elif [ "$__fvw_e" = u ]; then
            __fvw_mx=$__fvw_ux __fvw_my=$__fvw_uy
        elif [ "$__fvw_e" = z ]; then
            if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then fv.views._dragResized "$1"; fi
            return 0
        else
            return 0
        fi
    done
}

# fv.views._dragKeys V — DragView's keyboard part (the caller's _drag
# locals): FV's keys (a Shift in the name is FV's shift state: kbShiftLeft
# grows, kbCtrlShiftLeft grows by 8, kbShiftHome is Home), a step per key,
# until Enter (kept) or Esc (the start bounds back, FV Locate(SaveBounds)).
# The end of input counts as Esc (the modal loops end with cmCancel too); a
# cmResizeApp: fv.views._dragResized, no undo
fv.views._dragKeys() {
    local -n __fvw_dk=${1}_data
    local __fvw_e __fvw_k __fvw_sh __fvw_px __fvw_py __fvw_sx __fvw_sy __fvw_ux __fvw_uy
    local __fvw_b1=${__fvw_dk[OriginX]:-0} __fvw_b2=${__fvw_dk[OriginY]:-0} __fvw_b3 __fvw_b4
    __fvw_b3=$(( __fvw_b1 + ${__fvw_dk[SizeX]:-0} )) __fvw_b4=$(( __fvw_b2 + ${__fvw_dk[SizeY]:-0} ))
    while :; do
        fv.views._dragNext 1
        [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
        if [ "$__fvw_e" = z ]; then fv.views._dragResized "$1"; return 0; fi
        if [ "$__fvw_e" = e ]; then break; fi
        __fvw_px=${__fvw_dk[OriginX]:-0} __fvw_py=${__fvw_dk[OriginY]:-0} __fvw_sx=${__fvw_dk[SizeX]:-0} __fvw_sy=${__fvw_dk[SizeY]:-0}
        __fvw_k=$FV_EV_KEY __fvw_sh=0
        if [[ $__fvw_k == kb*Shift?* ]]; then __fvw_sh=1 __fvw_k=${__fvw_k%%Shift*}${__fvw_k#*Shift}; fi
        case $__fvw_k in
            kbLeft) fv.views._dragChange -1 0 ;;
            kbRight) fv.views._dragChange 1 0 ;;
            kbUp) fv.views._dragChange 0 -1 ;;
            kbDown) fv.views._dragChange 0 1 ;;
            kbCtrlLeft) fv.views._dragChange -8 0 ;;
            kbCtrlRight) fv.views._dragChange 8 0 ;;
            kbHome) if (( __fvw_m & FV_DM_DRAGMOVE )); then __fvw_px=$__fvw_l1; fi ;;
            kbEnd) if (( __fvw_m & FV_DM_DRAGMOVE )); then __fvw_px=$(( __fvw_l3 - __fvw_sx )); fi ;;
            kbPgUp) if (( __fvw_m & FV_DM_DRAGMOVE )); then __fvw_py=$__fvw_l2; fi ;;
            kbPgDn) if (( __fvw_m & FV_DM_DRAGMOVE )); then __fvw_py=$(( __fvw_l4 - __fvw_sy )); fi ;;
        esac
        fv.views._moveGrow "$1" "$__fvw_px" "$__fvw_py" "$__fvw_sx" "$__fvw_sy"
        # (FV's KeyCode: Shift+Enter / Shift+Esc end it as Enter / Esc)
        if [ "$__fvw_k" = kbEnter ]; then return 0; fi
        if [ "$__fvw_k" = kbEsc ]; then break; fi
    done
    if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then fv.views._locate "$1" "$__fvw_b1" "$__fvw_b2" "$__fvw_b3" "$__fvw_b4" || :; fi
}
# FV Change(DX, DY): move without the shift state (dmDragMove), grow with it
# (dmDragGrow) — on _dragKeys' locals
fv.views._dragChange() {
    if (( (__fvw_m & FV_DM_DRAGMOVE) && ! __fvw_sh )); then __fvw_px=$(( __fvw_px + $1 )) __fvw_py=$(( __fvw_py + $2 ))
    elif (( (__fvw_m & FV_DM_DRAGGROW) && __fvw_sh )); then __fvw_sx=$(( __fvw_sx + $1 )) __fvw_sy=$(( __fvw_sy + $2 )); fi
}

# fv.views._dragResized V — a resize mid-drag (design §2.3): the event
# source has handled it; the drag ends with V's bounds clamped (FV
# MoveGrow) into its owner's new extent, within its SizeLimits asked again
fv.views._dragResized() {
    local -n __fvw_rz=${1}_data
    local __fvw_o=${__fvw_rz[Owner]-}
    if [[ -n $__fvw_o && -n ${__FV_VW_LIVE[$__fvw_o]-} ]]; then
        local -n __fvw_ro=${__fvw_o}_data
        __fvw_l1=0 __fvw_l2=0 __fvw_l3=${__fvw_ro[SizeX]:-0} __fvw_l4=${__fvw_ro[SizeY]:-0}
        fv.views._virt "$1" SizeLimits || :
        __fvw_n1=$FV_MIN_X __fvw_n2=$FV_MIN_Y __fvw_x1=$FV_MAX_X __fvw_x2=$FV_MAX_Y
    fi
    fv.views._moveGrow "$1" "${__fvw_rz[OriginX]:-0}" "${__fvw_rz[OriginY]:-0}" "${__fvw_rz[SizeX]:-0}" "${__fvw_rz[SizeY]:-0}"
}

# ---- the frame's mouse (FPC TFrame.HandleEvent) ---------------------------------------

# TFrame.HandleEvent — FV: TView's, then a mouse-down on the frame (only a
# mouse-down reaches it: the dispatch skips it for the rest, and it is quiet
# for broadcasts): see fv.views._frameMouse
fv.views._frameEvent() {
    if ! [ "$FV_EV_WHAT" = evMouseDown ]; then return 0; fi
    fv.views._viewEvent "$1"
    if [ "$FV_EV_WHAT" = evMouseDown ]; then fv.views._frameMouse "$1"; fi
    return 0
}
# fv.views._frameMouse F — FV's cases, in the frame's coordinates:
#   * top row, sfActive, wfClose, X 2..4: the close icon tracked
#     (fv.views._frameIcon), cmClose posted for the owner;
#   * top row, sfActive, wfZoom, a double click anywhere on it or X W-5..W-3:
#     the zoom icon (tracked unless a double click), cmZoom posted;
#   * top row otherwise, wfMove: the owner dragged by the mouse (move);
#   * sfActive, X >= W-2 and Y >= H-1 (the grow corner), wfGrow: the owner
#     dragged by the mouse (grow).
# Each handles the event (FV_EV_INFO = the frame). The owner's Flags as the
# frame's draw reads them (not 1-9 digits: 0)
fv.views._frameMouse() {
    local -n __fvw_fd=${1}_data
    local __fvw_o=${__fvw_fd[Owner]-} __fvw_fl __fvw_x __fvw_y __fvw_w=${__fvw_fd[SizeX]:-0} __fvw_h=${__fvw_fd[SizeY]:-0} __fvw_a
    if [[ -z $__fvw_o || -z ${__FV_VW_LIVE[$__fvw_o]-} ]]; then return 0; fi
    local -n __fvw_fo=${__fvw_o}_data
    __fvw_fl=${__fvw_fo[Flags]:-0}
    if [[ $__fvw_fl == *[!0123456789]* || ${#__fvw_fl} -gt 9 ]]; then __fvw_fl=0; else __fvw_fl=$(( 10#$__fvw_fl )); fi
    __fvw_x=$(( FV_EV_MOUSE_X - __FV_VW_AX[$1] )) __fvw_y=$(( FV_EV_MOUSE_Y - __FV_VW_AY[$1] ))
    __fvw_a=$(( ${__fvw_fd[State]:-0} & FV_SF_ACTIVE ))
    if (( __fvw_y == 0 )); then
        if (( (__fvw_fl & FV_WF_CLOSE) && __fvw_a && __fvw_x >= 2 && __fvw_x <= 4 )); then
            fv.views._frameIcon "$1" 2 4 "$FV_FM_CLOSECLICKED" cmClose 0
        elif (( (__fvw_fl & FV_WF_ZOOM) && __fvw_a && (${FV_EV_MOUSE_DOUBLE:-0} == 1 || (__fvw_x >= __fvw_w - 5 && __fvw_x <= __fvw_w - 3)) )); then
            fv.views._frameIcon "$1" "$(( __fvw_w - 5 ))" "$(( __fvw_w - 3 ))" "$FV_FM_ZOOMCLICKED" cmZoom "$(( ${FV_EV_MOUSE_DOUBLE:-0} == 1 ))"
        elif (( __fvw_fl & FV_WF_MOVE )); then
            fv.views._dragWindow "$__fvw_o" "$FV_DM_DRAGMOVE" || :
            FV_EV_WHAT=evNothing FV_EV_INFO=$1
        fi
    elif (( __fvw_a && __fvw_x >= __fvw_w - 2 && __fvw_y >= __fvw_h - 1 && (__fvw_fl & FV_WF_GROW) )); then
        fv.views._dragWindow "$__fvw_o" "$FV_DM_DRAGGROW" || :
        FV_EV_WHAT=evNothing FV_EV_INFO=$1
    fi
    return 0
}

# fv.views._frameIcon F X1 X2 FM CMD DOUBLE — FV's press tracking of an icon on
# the top row (X1..X2): FrameMode = FM while the mouse is on it, 0 off it,
# through fv.views.mouseEvent (evMouseMove + evMouseAuto) until the mouse-up;
# the top row redrawn only when FrameMode changes (FV: DrawView on each
# event). On a mouse-up on the icon (or at once for DOUBLE: the zoom icon's
# double click) CMD is posted (__FV_VW_PUTEVENT, FV_EV_INFO = the owner). The
# release's own place decides (FV: the last place before it); the end of
# input posts nothing. The event record is put back, then handled
fv.views._frameIcon() {
    local -a __fvw_es
    local __fvw_in=1 __fvw_s __fvw_o
    local -n __fvw_id=${1}_data
    __fvw_o=${__fvw_id[Owner]-}
    # (the owner-process rule, as the drags: in a subshell nothing is read
    # or posted; the event is handled)
    if ! fv.views._ownerOk frameIcon; then FV_EV_WHAT=evNothing FV_EV_INFO=$1; return 0; fi
    fv.views._evSave
    if (( ! $6 )); then
        while :; do
            # (the frame or its window destroyed by the event source: out,
            # nothing drawn or posted)
            if [[ -z ${__FV_VW_LIVE[$1]-} || -z $__fvw_o || -z ${__FV_VW_LIVE[$__fvw_o]-} ]]; then __fvw_s=9; break; fi
            fv.views._frameOn "$1" "$2" "$3"
            fv.views._frameMode "$1" "$(( __fvw_in ? $4 : 0 ))"
            __fvw_s=0
            fv.views.mouseEvent "$1" "$(( FV_EM_MOUSEMOVE | FV_EM_MOUSEAUTO ))" || __fvw_s=$?
            if (( __fvw_s )); then break; fi
        done
        __fvw_in=0
        if (( __fvw_s == 1 )) && [ "$FV_EV_WHAT" = evMouseUp ] && [[ -n ${__FV_VW_LIVE[$1]-} ]]; then fv.views._frameOn "$1" "$2" "$3"; fi
    fi
    if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then fv.views._frameMode "$1" 0; fi
    if (( __fvw_in )); then
        fv.drivers.clearEvent
        FV_EV_WHAT=evCommand FV_EV_COMMAND=$5 FV_EV_INFO=$__fvw_o
        "$__FV_VW_PUTEVENT" || :
    fi
    fv.views._evRestore
    FV_EV_WHAT=evNothing FV_EV_INFO=$1
}
# the caller's __fvw_in = 1 when the mouse (FV_EV_MOUSE_*) is on F's top row
# at X1..X2
fv.views._frameOn() {
    local __fvw_x=$(( FV_EV_MOUSE_X - __FV_VW_AX[$1] ))
    if (( FV_EV_MOUSE_Y == __FV_VW_AY[$1] && __fvw_x >= $2 && __fvw_x <= $3 )); then __fvw_in=1; else __fvw_in=0; fi
}
# fv.views._frameMode F MODE — FrameMode := MODE; when it changed, the top row
# redrawn (a built-in Draw: drawPart of row 0 with fv.views._frameTopRow,
# one write; a Draw of yours: drawView)
fv.views._frameMode() {
    local -n __fvw_md=${1}_data
    if [ "${__fvw_md[FrameMode]:-0}" = "$2" ]; then return 0; fi
    __fvw_md[FrameMode]=$2
    local __fvw_o=${1}_class
    __fvw_o="${!__fvw_o-}_class_method_owner[Draw]"
    if [ "${__FV_VW_IMPL[${!__fvw_o-}.Draw]-}" = fv.views._frameDraw ]; then
        fv.views.drawPart "$1" fv.views._frameTopRow 0 1 || :
    else
        fv.views.drawView "$1" || :
    fi
}
# the drawPart painter: the frame's top row (the string cache)
fv.views._frameTopRow() {
    local __fvw_fc
    fv.views._frameRows "$1"
    fv.video._wbf "$FV_DRAW_X" "$FV_DRAW_Y" "${__FV_VW_FT[$__fvw_fc]}" "${__FV_VW_FTA[$__fvw_fc]}" || :
}

# ==== TScrollBar, TListViewer (P3 stage 3b; design P3 §1, §2.2, §2.3, §2.7, §3.3, §5) ====

# fv.views.ctrlToArrow KEY — FV CtrlToArrow: RESULT = the key a WordStar
# Ctrl key stands for (Ctrl+S D E X A F G V R C H -> kbLeft kbRight kbUp
# kbDown kbHome kbEnd kbDel kbIns kbPgUp kbPgDn kbBack), else KEY itself. One
# table read (__FV_VW_C2A; the widgets read the table inline)
fv.views.ctrlToArrow() {
    if (( $# != 1 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    RESULT=${__FV_VW_C2A[${1:-kbNoKey}]-$1}
}

# fv.views._track V MASK — the tracking loops' FV MouseEvent(Event, Mask):
# the next event whose bit is in MASK (rc 0, in FV_EV_*), what was drawn
# shown first; the others are dropped. rc 1 ends the loop: a mouse-up (FV)
# and, beyond FV, so that a lost release can never hold a loop (L2): a key
# (put back with __FV_VW_PUTEVENT, the loop's owner gets it next; FV_EV_WHAT
# evNothing), a resize the event source handled, the end of input (latched,
# FV_EV_WHAT evNothing). A mouse move is coalesced with the moves already
# waiting (fv.views._trackDrain, as dragView's R10). RESULT is kept
fv.views._track() {
    local __fvw_s __fvw_rz __fvw_r=${RESULT-}
    if [[ -n $__FV_VW_TRK ]]; then __FV_VW_TRK=''; FV_EV_WHAT=evMouseUp; return 1; fi
    while :; do
        fv.views._showNow
        if (( __FV_VW_EOF )); then FV_EV_WHAT=evNothing; RESULT=$__fvw_r; return 1; fi
        __fvw_s=0 __fvw_rz=$__FV_VW_RESIZES
        "$__FV_VW_GETEVENT" || __fvw_s=$?
        RESULT=$__fvw_r
        if (( __fvw_s )); then
            if (( __fvw_s != 1 )); then kk.debug "Error: fv.views: the event source '$__FV_VW_GETEVENT' failed (rc $__fvw_s): taken for the end of input"; fi
            __FV_VW_EOF=1 FV_EV_WHAT=evNothing
            return 1
        fi
        if (( __FV_VW_RESIZES != __fvw_rz )) || [ "$FV_EV_WHAT" = evMouseUp ]; then return 1; fi
        if [ "$FV_EV_WHAT" = evKeyDown ]; then "$__FV_VW_PUTEVENT" || :; FV_EV_WHAT=evNothing; return 1; fi
        if (( ${__FV_VW_EVBIT[${FV_EV_WHAT:-evNothing}]-0} & $2 )); then
            if [ "$FV_EV_WHAT" = evMouseMove ]; then fv.views._trackDrain; fi
            return 0
        fi
    done
}
# fv.views._trackDrain — _track's coalescing: the events already waiting
# ("$__FV_VW_GETEVENT" 0) are read; a move replaces the place; evNothing or
# an evMouseAuto stops; a mouse-up, a key (put back) or a resize stops and
# ends the NEXT _track (__FV_VW_TRK); the end of input stops (latched). The
# record is then the last move (FV processes every move; the last one before
# the release is the one that counts)
fv.views._trackDrain() {
    local __fvw_s __fvw_rz __fvw_mx=$FV_EV_MOUSE_X __fvw_my=$FV_EV_MOUSE_Y __fvw_mb=$FV_EV_MOUSE_BUTTONS __fvw_mm=$FV_EV_MOUSE_MODS
    while :; do
        __fvw_s=0 __fvw_rz=$__FV_VW_RESIZES
        "$__FV_VW_GETEVENT" 0 || __fvw_s=$?
        if (( __fvw_s )); then
            if (( __fvw_s != 1 )); then kk.debug "Error: fv.views: the event source '$__FV_VW_GETEVENT' failed (rc $__fvw_s): taken for the end of input"; fi
            __FV_VW_EOF=1
            break
        fi
        if (( __FV_VW_RESIZES != __fvw_rz )) || [ "$FV_EV_WHAT" = evMouseUp ]; then __FV_VW_TRK=1; break; fi
        if [ "$FV_EV_WHAT" = evMouseMove ]; then __fvw_mx=$FV_EV_MOUSE_X __fvw_my=$FV_EV_MOUSE_Y __fvw_mb=$FV_EV_MOUSE_BUTTONS __fvw_mm=$FV_EV_MOUSE_MODS
        elif [ "$FV_EV_WHAT" = evKeyDown ]; then "$__FV_VW_PUTEVENT" || :; __FV_VW_TRK=1; break
        elif [[ -z $FV_EV_WHAT ]] || [ "$FV_EV_WHAT" = evNothing ] || [ "$FV_EV_WHAT" = evMouseAuto ]; then break; fi
    done
    FV_EV_WHAT=evMouseMove FV_EV_MOUSE_X=$__fvw_mx FV_EV_MOUSE_Y=$__fvw_my FV_EV_MOUSE_BUTTONS=$__fvw_mb FV_EV_MOUSE_MODS=$__fvw_mm
}

# ---- TScrollBar (FV views.inc TScrollBar) ---------------------------------------

fv.views._sbCreate() {   # B
    local -n __fvw_bd=${1}_data
    __fvw_bd[EventMask]=$(( ${__fvw_bd[EventMask]:-0} | FV_EM_MOUSEWHEEL ))
    __fvw_bd[Value]=0 __fvw_bd[Min]=0 __fvw_bd[Max]=0 __fvw_bd[PgStep]=1 __fvw_bd[ArStep]=1 __fvw_bd[Id]=0
    if (( ${__fvw_bd[SizeX]:-0} == 1 )); then __fvw_bd[GrowMode]=$(( FV_GF_GROWLOX | FV_GF_GROWHIX | FV_GF_GROWHIY ))
    else __fvw_bd[GrowMode]=$(( FV_GF_GROWLOY | FV_GF_GROWHIX | FV_GF_GROWHIY )); fi
    __FV_VW_SB[$1]=1
}

# TScrollBar.GetPalette (func) — FV CScrollBar: page area, arrows, indicator
fv.views._sbGetPalette() { RESULT='4 5 5'; }

# fv.views._sbPos B — the caller's __fvw_sp = FV GetPos (the indicator's
# cell), __fvw_ss = GetSize (the length along the bar, at least 3)
fv.views._sbPos() {
    local -n __fvw_pd=${1}_data
    local __fvw_r=$(( ${__fvw_pd[Max]:-0} - ${__fvw_pd[Min]:-0} ))
    if (( ${__fvw_pd[SizeX]:-0} == 1 )); then __fvw_ss=${__fvw_pd[SizeY]:-0}; else __fvw_ss=${__fvw_pd[SizeX]:-0}; fi
    if (( __fvw_ss < 3 )); then __fvw_ss=3; fi
    if (( __fvw_r == 0 )); then __fvw_sp=1
    else __fvw_sp=$(( ((${__fvw_pd[Value]:-0} - ${__fvw_pd[Min]:-0}) * (__fvw_ss - 3) + (__fvw_r >> 1)) / __fvw_r + 1 )); fi
}

# TScrollBar.Draw — FV DrawPos(GetPos): the arrows in colour 2, the page area
# in colour 1 (▓ when Max = Min, else ▒ with the indicator ■ in colour 3);
# ASCII mode ^ v / < > : # # (design P3 §2.7: FV's LowAscii keeps the CP437
# shades, which fv.video's ASCII mode would show as ?). A vertical bar (1
# wide) is one writeLines of one-cell rows — only the rows the paint may
# change (the body is drawPart's painter too) — a horizontal one one
# writeLine, on every row of a taller bar (FV writes past its buffer there)
fv.views._sbDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    local -n __fvw_bd=${1}_data
    local __fvw_sp __fvw_ss __fvw_s __fvw_y __fvw_y2 __fvw_g0 __fvw_g1 __fvw_g2='▒' __fvw_g3='■' __fvw_e=$__FV_VW_ERRSYM
    local __fvw_c1=${FV_DRAW_PAL:0:1} __fvw_c2=${FV_DRAW_PAL:1:1} __fvw_c3=${FV_DRAW_PAL:2:1}
    local __fvw_n=$(( ${__fvw_bd[Max]:-0} == ${__fvw_bd[Min]:-0} ))
    fv.views._sbPos "$1"
    __fvw_s=$(( __fvw_ss - 1 ))
    __fvw_c1=${__fvw_c1:-$__fvw_e} __fvw_c2=${__fvw_c2:-$__fvw_e} __fvw_c3=${__fvw_c3:-$__fvw_e}
    if (( FV_VIDEO_ASCII )); then __fvw_g2=: __fvw_g3='#'; fi
    if (( __fvw_n )); then if (( FV_VIDEO_ASCII )); then __fvw_g2='#'; else __fvw_g2='▓'; fi; fi
    if (( ${__fvw_bd[SizeX]:-0} == 1 )); then
        if (( FV_VIDEO_ASCII )); then __fvw_g0='^' __fvw_g1=v; else __fvw_g0='▲' __fvw_g1='▼'; fi
        local -a _fvw_t=() _fvw_a=()
        __fvw_y2=$FV_CLIP_Y2
        if (( __fvw_y2 > ${__fvw_bd[SizeY]:-0} )); then __fvw_y2=${__fvw_bd[SizeY]:-0}; fi
        for (( __fvw_y = FV_CLIP_Y1; __fvw_y < __fvw_y2; __fvw_y++ )); do
            if (( __fvw_y == 0 )); then _fvw_t[0]=$__fvw_g0 _fvw_a[0]=$__fvw_c2
            elif (( __fvw_y == __fvw_s )); then _fvw_t[__fvw_y]=$__fvw_g1 _fvw_a[__fvw_y]=$__fvw_c2
            elif (( __fvw_y == __fvw_sp && ! __fvw_n )); then _fvw_t[__fvw_y]=$__fvw_g3 _fvw_a[__fvw_y]=$__fvw_c3
            else _fvw_t[__fvw_y]=$__fvw_g2 _fvw_a[__fvw_y]=$__fvw_c1; fi
        done
        if (( ${#_fvw_t[@]} )); then fv.views.writeLines 0 0 _fvw_t _fvw_a || :; fi
        return 0
    fi
    local __fvw_t __fvw_a __fvw_w=${__fvw_bd[SizeX]:-0}
    if (( __fvw_w < 1 || ${__fvw_bd[SizeY]:-0} < 1 )); then return 0; fi
    if (( FV_VIDEO_ASCII )); then __fvw_g0='<' __fvw_g1='>'; else __fvw_g0='◄' __fvw_g1='►'; fi
    if [[ -z ${__FV_VW_AT[$__fvw_c1]+x} ]]; then __FV_VW_AT[$__fvw_c1]=${__FV_VW_PAD// /"$__fvw_c1"}; fi
    # (the row is built and cut in ASCII stand-ins — 0 1 the arrows, blanks
    # the area, 3 the indicator — and the glyphs put in last: a cut never
    # meets a multi-byte glyph, so a caller in any locale gets the same row)
    __fvw_t=0${__FV_VW_PAD:0:__fvw_s-1}1 __fvw_a=$__fvw_c2${__FV_VW_AT[$__fvw_c1]:0:__fvw_s-1}$__fvw_c2
    if (( ! __fvw_n )); then __fvw_t=${__fvw_t:0:__fvw_sp}3${__fvw_t:__fvw_sp+1} __fvw_a=${__fvw_a:0:__fvw_sp}$__fvw_c3${__fvw_a:__fvw_sp+1}; fi
    __fvw_t=${__fvw_t:0:__fvw_w}
    __fvw_t=${__fvw_t// /"$__fvw_g2"} __fvw_t=${__fvw_t/0/"$__fvw_g0"}
    __fvw_t=${__fvw_t/1/"$__fvw_g1"} __fvw_t=${__fvw_t/3/"$__fvw_g3"}
    fv.views.writeLine 0 0 "${__fvw_bd[SizeY]}" "$__fvw_t" "${__fvw_a:0:__fvw_w}" || :
}

# TScrollBar.ScrollStep PART (func) — FV: ArStep for an arrow part (bit 1
# clear), PgStep for a page part, negative for an up / left part (bit 0
# clear). A PART that is not a number counts as 0
fv.views._sbScrollStep() {
    local -n __fvw_bd=${1}_data
    local __fvw_p=${2-} __fvw_s
    if [[ -z $__fvw_p || $__fvw_p == *[!0123456789]* || ${#__fvw_p} -gt 9 ]]; then __fvw_p=0; fi
    if (( (10#$__fvw_p & 2) == 0 )); then __fvw_s=${__fvw_bd[ArStep]:-1}; else __fvw_s=${__fvw_bd[PgStep]:-1}; fi
    if (( (10#$__fvw_p & 1) == 0 )); then RESULT=$(( -(__fvw_s) )); else RESULT=$(( __fvw_s )); fi
}

# TScrollBar.ScrollDraw — FV: Id <> 0 -> NewMessage(TopView, evCommand,
# cmIdCommunicate, Id, Value, Self); then NewMessage(Owner, evBroadcast,
# cmScrollBarChanged, Id, Value, Self). The record: FV_EV_ID = Id, FV_EV_INFO
# = the bar (FV's InfoPtr); FV's Data, the value, is the bar's Value field
# (synchronous messages: it holds exactly that value). A list moving its own
# bar is not told back (__FV_VW_QX, P3-4)
fv.views._sbScrollDraw() {
    local -n __fvw_bd=${1}_data
    local __fvw_i=${__fvw_bd[Id]:-0} __fvw_t __fvw_o=${__fvw_bd[Owner]-}
    if [[ -n $__fvw_i && $__fvw_i != 0 ]]; then
        fv.views._topView "$1"
        if [[ -n $__fvw_t ]]; then fv.views._message "$__fvw_t" evCommand cmIdCommunicate "$1" "$__fvw_i" || :; fi
    fi
    if [[ -n $__fvw_o && -n ${__FV_VW_LIVE[$1]-} && -n ${__FV_VW_LIVE[$__fvw_o]-} ]]; then
        fv.views._message "$__fvw_o" evBroadcast cmScrollBarChanged "$1" "$__fvw_i" || :
    fi
    return 0
}
# FV Clicked: NewMessage(Owner, evBroadcast, cmScrollBarClicked, Id, Value, Self)
fv.views._sbClicked() {
    local -n __fvw_bd=${1}_data
    local __fvw_o=${__fvw_bd[Owner]-}
    if [[ -n $__fvw_o && -n ${__FV_VW_LIVE[$__fvw_o]-} ]]; then fv.views._message "$__fvw_o" evBroadcast cmScrollBarClicked "$1" "${__fvw_bd[Id]:-0}" || :; fi
    return 0
}

# fv.views._sbSet B VALUE MIN MAX PG AR (integers) — FV SetParams with P3-4's
# redraw: MAX below MIN -> MIN, VALUE clamped into MIN .. MAX; when something
# changed: a range change draws the bar whole, a value change only the
# indicator's old and new cells (one drawPart over the rows from one to the
# other; nothing when the indicator stays: FV draws the bar every time), then
# ScrollDraw (virtual) when the value changed; PgStep / ArStep last (FV's
# order: a cmScrollBarChanged handler sees the old steps)
fv.views._sbSet() {
    local -n __fvw_bd=${1}_data
    local __fvw_v=$2 __fvw_n=$3 __fvw_x=$4 __fvw_ov=${__fvw_bd[Value]:-0} __fvw_sp __fvw_ss __fvw_op
    if (( __fvw_x < __fvw_n )); then __fvw_x=$__fvw_n; fi
    if (( __fvw_v < __fvw_n )); then __fvw_v=$__fvw_n; elif (( __fvw_v > __fvw_x )); then __fvw_v=$__fvw_x; fi
    if (( __fvw_n != ${__fvw_bd[Min]:-0} || __fvw_x != ${__fvw_bd[Max]:-0} )); then
        __fvw_bd[Min]=$__fvw_n __fvw_bd[Max]=$__fvw_x __fvw_bd[Value]=$__fvw_v
        fv.views._drawView "$1"
    elif (( __fvw_v != __fvw_ov )); then
        fv.views._sbPos "$1"
        __fvw_op=$__fvw_sp __fvw_bd[Value]=$__fvw_v
        fv.views._sbPos "$1"
        if (( __fvw_op != __fvw_sp )); then fv.views._sbThumb "$1"; fi
    fi
    if (( __fvw_v != __fvw_ov )); then fv.views._virt "$1" ScrollDraw || :; fi
    if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then __fvw_bd[PgStep]=$5 __fvw_bd[ArStep]=$6; fi
}
# fv.views._sbThumb B — _sbSet's indicator move (its __fvw_op, __fvw_sp): a
# vertical bar repaints the rows from the old cell to the new one (one
# drawPart with Draw's body as the painter), a horizontal one its row; a
# Draw of yours: drawView
fv.views._sbThumb() {
    local __fvw_o=${1}_class __fvw_a=$__fvw_op __fvw_b=$__fvw_sp
    __fvw_o="${!__fvw_o-}_class_method_owner[Draw]"
    if ! [ "${__FV_VW_IMPL[${!__fvw_o-}.Draw]-}" = fv.views._sbDraw ]; then fv.views._drawView "$1"; return 0; fi
    local -n __fvw_td=${1}_data
    if (( ${__fvw_td[SizeX]:-0} != 1 )); then __fvw_a=0 __fvw_b=$(( ${__fvw_td[SizeY]:-1} - 1 ))
    elif (( __fvw_a > __fvw_b )); then __fvw_a=$__fvw_sp __fvw_b=$__fvw_op; fi
    fv.views.drawPart "$1" fv.views._sbDraw "$__fvw_a" "$(( __fvw_b + 1 ))" || :
}

# fv.views.scrollBarSet SB VALUE [MIN MAX [PG AR]] — FV SetParams (VALUE MIN
# MAX PG AR), its SetValue (VALUE alone) and VALUE MIN MAX (the steps kept);
# the FV forms by name: `SB setValue VALUE`, `SB setRange MIN MAX`, `SB
# setStep PG AR`. The redraw of P3-4 and the cmScrollBarChanged broadcast
# when the value changed (fv.views._sbSet). RESULT is kept; rc 2: not a
# TScrollBar, not integers, a wrong count
fv.views.scrollBarSet() {
    if (( $# < 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._view "$1" scrollBarSet || return
    if [[ -z ${__FV_VW_SB[$1]-} ]]; then fv.views._bad scrollBarSet "'$1' is not a TScrollBar"; return; fi
    local -n __fvw_bd=${1}_data
    local -a __fvw_v
    local __fvw_r=${RESULT-} __fvw_a=${__fvw_bd[Value]:-0} __fvw_n=${__fvw_bd[Min]:-0} __fvw_x=${__fvw_bd[Max]:-0}
    local __fvw_p=${__fvw_bd[PgStep]:-1} __fvw_q=${__fvw_bd[ArStep]:-1} __fvw_k=$#
    if [ "$2" = setValue ] || [ "$2" = setRange ] || [ "$2" = setStep ]; then __fvw_k=x$2$#; fi
    case $__fvw_k in
        2) fv.views._ints "$2" && __fvw_a=${__fvw_v[0]} ;;
        4) fv.views._ints "$2" "$3" "$4" && __fvw_a=${__fvw_v[0]} __fvw_n=${__fvw_v[1]} __fvw_x=${__fvw_v[2]} ;;
        6) fv.views._ints "$2" "$3" "$4" "$5" "$6" && __fvw_a=${__fvw_v[0]} __fvw_n=${__fvw_v[1]} __fvw_x=${__fvw_v[2]} __fvw_p=${__fvw_v[3]} __fvw_q=${__fvw_v[4]} ;;
        xsetValue3) fv.views._ints "$3" && __fvw_a=${__fvw_v[0]} ;;
        xsetRange4) fv.views._ints "$3" "$4" && __fvw_n=${__fvw_v[0]} __fvw_x=${__fvw_v[1]} ;;
        xsetStep4) fv.views._ints "$3" "$4" && __fvw_p=${__fvw_v[0]} __fvw_q=${__fvw_v[1]} ;;
        *) fv.views._bad scrollBarSet 'SB VALUE [MIN MAX [PG AR]], SB setValue V, SB setRange MIN MAX or SB setStep PG AR'; return ;;
    esac || { fv.views._bad scrollBarSet 'the numbers must be integers'; return; }
    fv.views._sbSet "$1" "$__fvw_a" "$__fvw_n" "$__fvw_x" "$__fvw_p" "$__fvw_q"
    RESULT=$__fvw_r
}

# TScrollBar.HandleEvent — FV: TView's (a mouse-down), then
#   * evCommand cmIdCommunicate whose FV_EV_ID is Id, from another view: its
#     value (the sender's Value field, or an integer FV_EV_INFO) set, handled;
#   * evKeyDown while visible (a bar gets keys through ofPostProcess:
#     FV_SB_HANDLEKEYBOARD): fv.views._sbKey;
#   * evMouseWheel: Clicked, then Value -/+ ArStep (a double wheel event and
#     ArStep 1: 6, FV), handled;
#   * evMouseDown: fv.views._sbMouse
fv.views._sbEvent() {
    if [ "$FV_EV_WHAT" = evMouseDown ]; then
        fv.views._viewEvent "$1"
        if [ "$FV_EV_WHAT" = evMouseDown ]; then fv.views._sbMouse "$1"; fi
    elif [ "$FV_EV_WHAT" = evKeyDown ]; then fv.views._sbKey "$1"
    elif [ "$FV_EV_WHAT" = evMouseWheel ]; then fv.views._sbWheel "$1"
    elif [ "$FV_EV_WHAT" = evCommand ] && [ "$FV_EV_COMMAND" = cmIdCommunicate ]; then fv.views._sbIdc "$1"; fi
    return 0
}
fv.views._sbIdc() {   # B (cmIdCommunicate)
    local -n __fvw_bd=${1}_data
    local -a __fvw_v
    local __fvw_q=$FV_EV_INFO
    if [ "$FV_EV_ID" != "${__fvw_bd[Id]:-0}" ] || [ "$FV_EV_INFO" = "$1" ]; then return 0; fi
    if [[ -n $__fvw_q && -n ${__FV_VW_LIVE[$__fvw_q]-} ]]; then __fvw_q="${__fvw_q}_data[Value]" __fvw_q=${!__fvw_q-}; fi
    fv.views._ints "$__fvw_q" || return 0
    fv.views._sbSet "$1" "${__fvw_v[0]}" "${__fvw_bd[Min]:-0}" "${__fvw_bd[Max]:-0}" "${__fvw_bd[PgStep]:-1}" "${__fvw_bd[ArStep]:-1}"
    FV_EV_WHAT=evNothing FV_EV_INFO=$1
}
# fv.views._sbKey B — FV's keys (through CtrlToArrow) of a visible bar: a
# horizontal one (1 high) Left / Right (arrow), Ctrl+Left / Ctrl+Right
# (page), Home / End (Min / Max); a vertical one Up / Down, PgUp / PgDn,
# Ctrl+PgUp / Ctrl+PgDn (Min / Max). Clicked, then the value set (an arrow or
# page part by ScrollStep, virtual), handled
fv.views._sbKey() {
    local -n __fvw_bd=${1}_data
    if (( ! (${__fvw_bd[State]:-0} & FV_SF_VISIBLE) )); then return 0; fi
    local __fvw_k=${__FV_VW_C2A[${FV_EV_KEY:-kbNoKey}]-$FV_EV_KEY} __fvw_p=$FV_SB_INDICATOR __fvw_i=${__fvw_bd[Value]:-0}
    if (( ${__fvw_bd[SizeY]:-0} == 1 )); then
        case $__fvw_k in
            kbLeft) __fvw_p=$FV_SB_LEFTARROW ;; kbRight) __fvw_p=$FV_SB_RIGHTARROW ;;
            kbCtrlLeft) __fvw_p=$FV_SB_PAGELEFT ;; kbCtrlRight) __fvw_p=$FV_SB_PAGERIGHT ;;
            kbHome) __fvw_i=${__fvw_bd[Min]:-0} ;; kbEnd) __fvw_i=${__fvw_bd[Max]:-0} ;;
            *) return 0 ;;
        esac
    else
        case $__fvw_k in
            kbUp) __fvw_p=$FV_SB_UPARROW ;; kbDown) __fvw_p=$FV_SB_DOWNARROW ;;
            kbPgUp) __fvw_p=$FV_SB_PAGEUP ;; kbPgDn) __fvw_p=$FV_SB_PAGEDOWN ;;
            kbCtrlPgUp) __fvw_i=${__fvw_bd[Min]:-0} ;; kbCtrlPgDn) __fvw_i=${__fvw_bd[Max]:-0} ;;
            *) return 0 ;;
        esac
    fi
    fv.views._sbClicked "$1"
    if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then
        if (( __fvw_p != FV_SB_INDICATOR )); then
            fv.views._virt "$1" ScrollStep "$__fvw_p" || RESULT=0
            __fvw_i=$(( ${__fvw_bd[Value]:-0} + RESULT ))
        fi
        fv.views._sbSet "$1" "$__fvw_i" "${__fvw_bd[Min]:-0}" "${__fvw_bd[Max]:-0}" "${__fvw_bd[PgStep]:-1}" "${__fvw_bd[ArStep]:-1}"
    fi
    FV_EV_WHAT=evNothing FV_EV_INFO=$1
}
fv.views._sbWheel() {   # B (evMouseWheel)
    local -n __fvw_bd=${1}_data
    local __fvw_a=${__fvw_bd[ArStep]:-1}
    fv.views._sbClicked "$1"
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    if (( __fvw_a == 1 && ${FV_EV_MOUSE_DOUBLE:-0} == 1 )); then __fvw_a=6; fi
    if (( FV_EV_WHEEL == 1 )); then __fvw_a=$(( -__fvw_a )); elif (( FV_EV_WHEEL != 2 )); then return 0; fi
    fv.views._sbSet "$1" "$(( ${__fvw_bd[Value]:-0} + __fvw_a ))" "${__fvw_bd[Min]:-0}" "${__fvw_bd[Max]:-0}" "${__fvw_bd[PgStep]:-1}" "${__fvw_bd[ArStep]:-1}"
    FV_EV_WHAT=evNothing FV_EV_INFO=$1
}
# fv.views._sbPart B — the caller's __fvw_m = FV GetPartCode for the mouse
# (FV_EV_MOUSE_*): -1 outside the bar, else the part, with the indicator's
# cell __fvw_p and the size __fvw_ss of the caller (FV takes both at the press)
fv.views._sbPart() {
    local -n __fvw_qd=${1}_data
    local __fvw_x=$(( FV_EV_MOUSE_X - __FV_VW_AX[$1] )) __fvw_y=$(( FV_EV_MOUSE_Y - __FV_VW_AY[$1] )) __fvw_k
    __fvw_m=-1
    if (( __fvw_x < 0 || __fvw_y < 0 || __fvw_x >= ${__fvw_qd[SizeX]:-0} || __fvw_y >= ${__fvw_qd[SizeY]:-0} )); then return 0; fi
    if (( ${__fvw_qd[SizeX]:-0} == 1 )); then __fvw_k=$__fvw_y; else __fvw_k=$__fvw_x; fi
    if (( __fvw_k == __fvw_p )); then __fvw_m=$FV_SB_INDICATOR; return 0; fi
    if (( __fvw_k < 1 )); then __fvw_m=$FV_SB_LEFTARROW
    elif (( __fvw_k < __fvw_p )); then __fvw_m=$FV_SB_PAGELEFT
    elif (( __fvw_k < __fvw_ss - 1 )); then __fvw_m=$FV_SB_PAGERIGHT
    else __fvw_m=$FV_SB_RIGHTARROW; fi
    if (( ${__fvw_qd[SizeX]:-0} == 1 )); then __fvw_m=$(( __fvw_m + 4 )); fi
}
# fv.views._sbMouse B — FV's mouse-down: Clicked; the part under the mouse
# with the indicator's cell and the size taken at the press (FV): an arrow
# or a page part steps (ScrollStep) at once and again on every evMouseAuto
# while the mouse is on that part (FV P3-8: held, the first after
# FV_REPEAT_DELAY), until the release, then Clicked; the indicator follows
# the mouse (moves, coalesced) while it is inside the bar (outside: back to
# where the value puts it) until the release, then Clicked when the value
# changed. A key ends the tracking as a release does (fv.views._track).
# Handled
fv.views._sbMouse() {
    local -n __fvw_bd=${1}_data
    local __fvw_sp __fvw_ss __fvw_p __fvw_c __fvw_m __fvw_i __fvw_iv __fvw_tr=0 __fvw_x __fvw_y
    fv.views._sbClicked "$1"
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    # (a release an earlier loop's drain met and never used is not this one's)
    __FV_VW_TRK=''
    fv.views._sbPos "$1"
    __fvw_p=$__fvw_sp
    fv.views._sbPart "$1"
    __fvw_c=$__fvw_m
    if (( __fvw_c != FV_SB_INDICATOR )); then
        while :; do
            fv.views._sbPart "$1"
            if (( __fvw_m == __fvw_c && __fvw_c >= 0 )); then
                fv.views._virt "$1" ScrollStep "$__fvw_c" || RESULT=0
                fv.views._sbSet "$1" "$(( ${__fvw_bd[Value]:-0} + RESULT ))" "${__fvw_bd[Min]:-0}" "${__fvw_bd[Max]:-0}" "${__fvw_bd[PgStep]:-1}" "${__fvw_bd[ArStep]:-1}"
            fi
            [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
            fv.views._track "$1" "$FV_EM_MOUSEAUTO" || break
        done
        fv.views._sbClicked "$1"
    else
        __fvw_iv=${__fvw_bd[Value]:-0}
        while :; do
            __fvw_x=$(( FV_EV_MOUSE_X - __FV_VW_AX[$1] )) __fvw_y=$(( FV_EV_MOUSE_Y - __FV_VW_AY[$1] ))
            if (( __fvw_x >= 0 && __fvw_y >= 0 && __fvw_x < ${__fvw_bd[SizeX]:-0} && __fvw_y < ${__fvw_bd[SizeY]:-0} )); then
                __fvw_tr=1
                if (( ${__fvw_bd[SizeX]:-0} == 1 )); then __fvw_i=$__fvw_y; else __fvw_i=$__fvw_x; fi
                if (( __fvw_i > __fvw_ss )); then __fvw_i=$__fvw_ss; fi
            else
                __fvw_tr=0
                fv.views._sbPos "$1"
                __fvw_i=$__fvw_sp
            fi
            if (( __fvw_i != __fvw_p )); then
                fv.views._sbSet "$1" "$(( (__fvw_i * (${__fvw_bd[Max]:-0} - ${__fvw_bd[Min]:-0}) + (__fvw_ss >> 1)) / __fvw_ss + ${__fvw_bd[Min]:-0} ))" \
                    "${__fvw_bd[Min]:-0}" "${__fvw_bd[Max]:-0}" "${__fvw_bd[PgStep]:-1}" "${__fvw_bd[ArStep]:-1}"
                __fvw_p=$__fvw_i
            fi
            [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
            fv.views._track "$1" "$FV_EM_MOUSEMOVE" || break
        done
        if (( __fvw_tr )); then
            fv.views._sbSet "$1" "$(( (__fvw_p * (${__fvw_bd[Max]:-0} - ${__fvw_bd[Min]:-0}) + (__fvw_ss >> 1)) / __fvw_ss + ${__fvw_bd[Min]:-0} ))" \
                "${__fvw_bd[Min]:-0}" "${__fvw_bd[Max]:-0}" "${__fvw_bd[PgStep]:-1}" "${__fvw_bd[ArStep]:-1}"
        fi
        if [[ -n ${__FV_VW_LIVE[$1]-} ]] && (( __fvw_iv != ${__fvw_bd[Value]:-0} )); then fv.views._sbClicked "$1"; fi
    fi
    FV_EV_WHAT=evNothing FV_EV_INFO=$1
}

# fv.views.standardScrollBar W OPTIONS — FV TWindow.StandardScrollBar: a
# TScrollBar on W's frame — FV_SB_VERTICAL in OPTIONS: the right column, rows
# 1 .. SizeY-2; else the bottom row, columns 2 .. SizeX-3 — inserted into W,
# with ofPostProcess for FV_SB_HANDLEKEYBOARD; RESULT = its name (reserved:
# W__fvsbN, the first free N from 1). rc 2: W not a group, OPTIONS not an
# integer, a wrong count
fv.views.standardScrollBar() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._group "$1" standardScrollBar || return
    local -a __fvw_v
    if ! fv.views._ints "$2"; then fv.views._bad standardScrollBar 'OPTIONS must be an integer (FV_SB_* bits)'; return; fi
    local -n __fvw_wd=${1}_data
    local __fvw_w=${__fvw_wd[SizeX]:-0} __fvw_h=${__fvw_wd[SizeY]:-0} __fvw_o=${__fvw_v[0]} __fvw_k=1 __fvw_n __fvw_s=0
    while [[ -n ${__FV_VW_LIVE[${1}__fvsb$__fvw_k]-} ]]; do __fvw_k=$(( __fvw_k + 1 )); done
    if (( __fvw_o & FV_SB_VERTICAL )); then
        fv.views._newReserved "$1" "sb$__fvw_k" TScrollBar "$(( __fvw_w - 1 ))" 1 "$__fvw_w" "$(( __fvw_h - 1 ))" || __fvw_s=$?
    else
        fv.views._newReserved "$1" "sb$__fvw_k" TScrollBar 2 "$(( __fvw_h - 1 ))" "$(( __fvw_w - 2 ))" "$__fvw_h" || __fvw_s=$?
    fi
    __fvw_n=$RESULT
    if (( __fvw_s )) || [[ -z ${__FV_VW_LIVE[$__fvw_n]-} ]]; then RESULT=''; return 2; fi
    if (( __fvw_o & FV_SB_HANDLEKEYBOARD )); then
        local -n __fvw_bd=${__fvw_n}_data
        __fvw_bd[Options]=$(( ${__fvw_bd[Options]:-0} | FV_OF_POSTPROCESS ))
    fi
    fv.views.insert "$1" "$__fvw_n" || :
    RESULT=$__fvw_n
}

# ---- TListViewer (FV views.inc TListViewer, FPC 2025; design P3 §2.2, §5) ---------

# fv.views._lvArgs V [NUMCOLS [HSB [VSB]]] — the constructor's refusals,
# before anything is made: rc 2 and one Error line
fv.views._lvArgs() {
    local __fvw_n=${2:-1} __fvw_b
    if [[ $__fvw_n == *[!0123456789]* || ${#__fvw_n} -gt 4 ]] || (( 10#$__fvw_n < 1 || 10#$__fvw_n > __FV_VW_MAXW )); then
        fv.views._err "TListViewer.Create: '$1': NUMCOLS must be 1..$__FV_VW_MAXW (got: $__fvw_n)"
        __FV_VW_CRC=2
        return 2
    fi
    for __fvw_b in "${3-}" "${4-}"; do
        if [[ -n $__fvw_b && -z ${__FV_VW_SB[$__fvw_b]-} ]]; then
            fv.views._err "TListViewer.Create: '$1': a scroll bar must be '' or a live TScrollBar (got: $__fvw_b)"
            __FV_VW_CRC=2
            return 2
        fi
    done
}
fv.views._lvCreate() {   # V NUMCOLS HSB VSB
    local -n __fvw_ld=${1}_data
    __fvw_ld[Options]=$(( ${__fvw_ld[Options]:-0} | FV_OF_FIRSTCLICK | FV_OF_SELECTABLE ))
    __fvw_ld[EventMask]=$(( ${__fvw_ld[EventMask]:-0} | FV_EM_BROADCAST | FV_EM_MOUSEWHEEL ))
    __fvw_ld[NumCols]=$(( 10#$2 )) __fvw_ld[TopItem]=0 __fvw_ld[Focused]=0 __fvw_ld[Range]=0
    __fvw_ld[List]='' __fvw_ld[Formatter]='' __fvw_ld[Marks]=''
    __FV_VW_LY[$1]=0
    if [[ -n $3 ]]; then
        local -n __fvw_hd=${3}_data
        fv.views._sbSet "$3" "${__fvw_hd[Value]:-0}" "${__fvw_hd[Min]:-0}" "${__fvw_hd[Max]:-0}" "$(( ${__fvw_ld[SizeX]:-0} / __fvw_ld[NumCols] ))" 1
    fi
    __fvw_ld[HScrollBar]=$3 __fvw_ld[VScrollBar]=$4
}
# fv.views._list V CALLER — rc 0 for a live TListViewer (LY is set by its
# constructor); else rc 2 (fv.views._bad / _view)
fv.views._list() {
    fv.views._view "$1" "$2" || return
    if [[ -z ${__FV_VW_LY[$1]+x} ]]; then fv.views._bad "$2" "'$1' is not a TListViewer"; return; fi
}
# fv.views._lvName NAME — rc 0 when NAME may be List / Marks: an identifier
# that does not start with _fv or __fv in any case (reserved: fv.views' own
# globals and locals — the painters' arrays _fvw_t _fvw_a _fvw_r ... — which
# a nameref to such a name would reach instead of the caller's array)
fv.views._lvName() {
    [[ -n $1 && $1 != *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]* && $1 != [0123456789]* && $1 != _[fF][vV]* && $1 != __[fF][vV]* ]]
}

# TListViewer.GetPalette (func) — FV CListViewer 26 26 27 28 29 when the
# owner's resolved palette reaches entry 29 (a dialog; no owner: the app
# palette); in a plain window (8 entries) the window's scroller entries
# 6 6 7 2 6 instead of FV's ErrorAttr (D25, a documented deviation; a
# marked row, colour 4, takes the window's entry 2 — bright white on blue
# in a blue window — so that marks show, owner 2026-11-21; the focused row
# keeps entry 7 even when marked: FV, focus wins)
fv.views._lvGetPalette() {
    local -n __fvw_ld=${1}_data
    local __fvw_o=${__fvw_ld[Owner]-}
    if [[ -n $__fvw_o && -n ${__FV_VW_LIVE[$__fvw_o]-} ]]; then
        if [[ -z ${__FV_VW_PAL[$__fvw_o]+x} ]]; then fv.views._pal "$__fvw_o"; fi
        if (( ${#__FV_VW_PAL[$__fvw_o]} < 29 )); then RESULT='6 6 7 2 6'; return 0; fi
    fi
    RESULT='26 26 27 28 29'
}

# TListViewer.Draw — FV's rows (design P3 §2.2): item J*SizeY + I + TopItem
# in column J of row I; ColWidth = SizeX div NumCols + 1; a column is a
# blank, the item's text (FV GetText = List[i], or Formatter i ColWidth+Indent)
# and the divider │ in colour 5 at its last cell (the last column's lies past
# the row, as in FV); colour per FPC 2025's GetItemColor: the focused item of
# a selected + active list (Range > 0) 3, a selected item below Range 4
# (IsSelected: the focused one or a set Marks entry, D26), else 2. Only the
# rows the paint may change (FV_CLIP_Y1 .. Y2: the body is drawPart's
# painter too). Rows of printable ASCII: one writeLines (one row: writeLine);
# any other text: one writeRows (cut by fv.video's cells, P3 10.2). Here the
# common case (one column, no horizontal bar, the built-in IsSelected, List /
# Marks plain identifiers); the rest: fv.views._lvDrawX
fv.views._lvDraw() {
    if ! [ "${FV_DRAW_VIEW-}" = "$1" ]; then return 0; fi
    if [[ ( $BASHOPTS == *nocasematch* || $BASHOPTS != *globasciiranges* || ${#__FV_VS_PB} != 2 ) && -z ${__fvv_g-} ]]; then fv.video._g fv.views._lvDraw "$1"; return; fi
    local -n __fvw_ld=${1}_data
    local __fvw_o=${1}_class __fvw_l=${__fvw_ld[List]-} __fvw_m=${__fvw_ld[Marks]-} __fvw_fm=${__fvw_ld[Formatter]-}
    __fvw_o="${!__fvw_o-}_class_method_owner[IsSelected]"
    if [[ ${__fvw_ld[NumCols]:-1} != 1 || -n ${__fvw_ld[HScrollBar]-} || $__fvw_l$__fvw_m == *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]* \
          || $__fvw_l == [0123456789_]* || $__fvw_m == [0123456789_]* ]] || ! [ "${__FV_VW_IMPL[${!__fvw_o-}.IsSelected]-}" = fv.views._lvIsSelected ]; then
        fv.views._lvDrawX "$1"
        return
    fi
    local __fvw_w=${__fvw_ld[SizeX]:-0} __fvw_t=${__fvw_ld[TopItem]:-0} __fvw_f=${__fvw_ld[Focused]:-0} __fvw_n=${__fvw_ld[Range]:-0}
    local __fvw_y=$FV_CLIP_Y1 __fvw_y2=$FV_CLIP_Y2 __fvw_i __fvw_s __fvw_c __fvw_e=$__FV_VW_ERRSYM
    local __fvw_c2=${FV_DRAW_PAL:1:1} __fvw_c3=${FV_DRAW_PAL:2:1} __fvw_c4=${FV_DRAW_PAL:3:1}
    if (( __fvw_y2 > ${__fvw_ld[SizeY]:-0} )); then __fvw_y2=${__fvw_ld[SizeY]:-0}; fi
    if (( __fvw_y >= __fvw_y2 || __fvw_w < 1 )); then return 0; fi
    __fvw_c2=${__fvw_c2:-$__fvw_e} __fvw_c3=${__fvw_c3:-$__fvw_e} __fvw_c4=${__fvw_c4:-$__fvw_e}
    # (the focused item: 3 in a selected + active list, else 4 — IsSelected)
    if (( (${__fvw_ld[State]:-0} & (FV_SF_SELECTED | FV_SF_ACTIVE)) != (FV_SF_SELECTED | FV_SF_ACTIVE) )); then __fvw_c3=$__fvw_c4
    elif (( __fvw_f >= __fvw_t + __fvw_y && __fvw_f < __fvw_t + __fvw_y2 && __fvw_f < __fvw_n )); then
        __fvw_ld[CursorX]=1 __fvw_ld[CursorY]=$(( __fvw_f - __fvw_t ))
    fi
    for __fvw_c in "$__fvw_c2" "$__fvw_c3" "$__fvw_c4"; do
        if [[ -z ${__FV_VW_AT[$__fvw_c]+x} ]]; then __FV_VW_AT[$__fvw_c]=${__FV_VW_PAD// /"$__fvw_c"}; fi
    done
    if [[ -n $__fvw_l ]]; then local -n __fvw_la=$__fvw_l; else local -a __fvw_la=(); fi
    if [[ -n $__fvw_m ]]; then local -n __fvw_ma=$__fvw_m; else local -a __fvw_ma=(); fi
    if [[ -n $__fvw_fm && -z ${__FV_VW_FOK[$__fvw_fm]-} ]]; then fv.views._lvFmt; fi
    local -a _fvw_t=() _fvw_a=() _fvw_r=() _fvw_s=()
    for (( ; __fvw_y < __fvw_y2; __fvw_y++ )); do
        __fvw_i=$(( __fvw_t + __fvw_y ))
        if (( __fvw_i < __fvw_n && __fvw_i >= 0 )); then
            if [[ -n $__fvw_fm ]]; then "$__fvw_fm" "$__fvw_i" "$(( __fvw_w + 1 ))"; __fvw_s=" $RESULT"; else __fvw_s=" ${__fvw_la[$__fvw_i]-}"; fi
            if (( __fvw_i == __fvw_f )); then __fvw_c=$__fvw_c3
            elif [[ ${__fvw_ma[$__fvw_i]:-0} != 0 ]]; then __fvw_c=$__fvw_c4
            else __fvw_c=$__fvw_c2; fi
        else __fvw_s='' __fvw_c=$__fvw_c2; fi
        _fvw_r[__fvw_y]=$__fvw_s _fvw_s[__fvw_y]=$__fvw_c
        __fvw_s+=$__FV_VW_PAD
        _fvw_t[__fvw_y]=${__fvw_s:0:__fvw_w} _fvw_a[__fvw_y]=${__FV_VW_AT[$__fvw_c]:0:__fvw_w}
    done
    # (the rows joined by a blank whatever the caller's IFS: a newline or a
    # tab there would send every ASCII page down the writeRows path)
    local IFS=' '
    if [[ ${_fvw_r[*]} != $__FV_VS_PNA ]]; then
        if (( __fvw_y2 - FV_CLIP_Y1 == 1 )); then fv.views.writeLine 0 "$FV_CLIP_Y1" 1 "${_fvw_t[FV_CLIP_Y1]}" "${_fvw_a[FV_CLIP_Y1]}" || :
        else fv.views.writeLines 0 0 _fvw_t _fvw_a || :; fi
    else
        fv.views._lvWide "$__fvw_w"
        fv.views.writeRows 0 0 "$__fvw_w" _fvw_r _fvw_s || :
    fi
}
# fv.views._lvWide W — the caller's rows _fvw_r cut to 4 W characters (a
# text far longer than the row costs fv.video's walk for nothing)
fv.views._lvWide() {
    local __fvw_k __fvw_x=$(( $1 * 4 ))
    for __fvw_k in "${!_fvw_r[@]}"; do
        if (( ${#_fvw_r[__fvw_k]} > __fvw_x )); then _fvw_r[__fvw_k]=${_fvw_r[__fvw_k]:0:__fvw_x}; fi
    done
}
# fv.views._lvFmt — the caller's Formatter __fvw_fm checked once per name
# (declare -F); not a function: '' (the items' own text), one debug line
fv.views._lvFmt() {
    if declare -F "$__fvw_fm" >/dev/null; then __FV_VW_FOK[$__fvw_fm]=1
    else kk.debug "Error: fv.views: TListViewer.Draw: Formatter '$__fvw_fm' is not a function (ignored)"; __fvw_fm=''; fi
}

# fv.views._lvDrawX V — TListViewer.Draw's general case: NumCols columns, the
# indent of a horizontal bar (FV: the text from character Indent on, Pascal's
# Copy: 0 and 1 both from the first), IsSelected through the elision per item
# when the class overrides it (a dispatch each, documented), List / Marks
# names that are no identifier or reserved (_fv*, __fv*: fv.views._lvName):
# none. Rows of printable ASCII: one writeLines (each row composed: blank +
# text + divider per column); any other text: per column one writeRows of
# its texts, and one writeLines per divider column
fv.views._lvDrawX() {
    local -n __fvw_ld=${1}_data
    local __fvw_l=${__fvw_ld[List]-} __fvw_m=${__fvw_ld[Marks]-} __fvw_fm=${__fvw_ld[Formatter]-} __fvw_b=${__fvw_ld[HScrollBar]-}
    local __fvw_w=${__fvw_ld[SizeX]:-0} __fvw_h=${__fvw_ld[SizeY]:-0} __fvw_nc=${__fvw_ld[NumCols]:-1} __fvw_t=${__fvw_ld[TopItem]:-0}
    local __fvw_f=${__fvw_ld[Focused]:-0} __fvw_n=${__fvw_ld[Range]:-0} __fvw_in=0 __fvw_sk=0 __fvw_isb=1 __fvw_act=0 __fvw_o=${1}_class
    local __fvw_y __fvw_y2=$FV_CLIP_Y2 __fvw_j __fvw_i __fvw_x __fvw_k __fvw_s __fvw_c __fvw_cw __fvw_rt __fvw_ra __fvw_e=$__FV_VW_ERRSYM
    local __fvw_c2=${FV_DRAW_PAL:1:1} __fvw_c3=${FV_DRAW_PAL:2:1} __fvw_c4=${FV_DRAW_PAL:3:1} __fvw_c5=${FV_DRAW_PAL:4:1}
    if [[ $__fvw_nc == *[!0123456789]* || -z $__fvw_nc ]] || (( __fvw_nc < 1 )); then __fvw_nc=1; fi
    if (( __fvw_y2 > __fvw_h )); then __fvw_y2=$__fvw_h; fi
    if (( FV_CLIP_Y1 >= __fvw_y2 || __fvw_w < 1 )); then return 0; fi
    __fvw_c2=${__fvw_c2:-$__fvw_e} __fvw_c3=${__fvw_c3:-$__fvw_e} __fvw_c4=${__fvw_c4:-$__fvw_e} __fvw_c5=${__fvw_c5:-$__fvw_e}
    __fvw_cw=$(( __fvw_w / __fvw_nc + 1 ))
    if [[ -n $__fvw_b && -n ${__FV_VW_SB[$__fvw_b]-} ]]; then
        __fvw_in="${__fvw_b}_data[Value]" __fvw_in=${!__fvw_in:-0}
        if (( __fvw_in > 1 )); then __fvw_sk=$(( __fvw_in - 1 )); fi
    fi
    __fvw_o="${!__fvw_o-}_class_method_owner[IsSelected]"
    if ! [ "${__FV_VW_IMPL[${!__fvw_o-}.IsSelected]-}" = fv.views._lvIsSelected ]; then __fvw_isb=0; fi
    if (( (${__fvw_ld[State]:-0} & (FV_SF_SELECTED | FV_SF_ACTIVE)) == (FV_SF_SELECTED | FV_SF_ACTIVE) && __fvw_n > 0 )); then __fvw_act=1; fi
    if ! fv.views._lvName "$__fvw_l"; then __fvw_l=''; fi
    if ! fv.views._lvName "$__fvw_m"; then __fvw_m=''; fi
    if [[ -n $__fvw_l ]]; then local -n __fvw_la=$__fvw_l; else local -a __fvw_la=(); fi
    if [[ -n $__fvw_m ]]; then local -n __fvw_ma=$__fvw_m; else local -a __fvw_ma=(); fi
    if [[ -n $__fvw_fm && -z ${__FV_VW_FOK[$__fvw_fm]-} ]]; then fv.views._lvFmt; fi
    for __fvw_c in "$__fvw_c2" "$__fvw_c3" "$__fvw_c4" "$__fvw_c5"; do
        if [[ -z ${__FV_VW_AT[$__fvw_c]+x} ]]; then __FV_VW_AT[$__fvw_c]=${__FV_VW_PAD// /"$__fvw_c"}; fi
    done
    # per cell (row y, column j): _fvw_x[y*nc+j] text, _fvw_s[...] its symbol
    local -a _fvw_x=() _fvw_s=() _fvw_t=() _fvw_a=() _fvw_r=() _fvw_q=()
    for (( __fvw_y = FV_CLIP_Y1; __fvw_y < __fvw_y2; __fvw_y++ )); do
        for (( __fvw_j = 0; __fvw_j < __fvw_nc; __fvw_j++ )); do
            __fvw_x=$(( __fvw_j * __fvw_cw ))
            if (( __fvw_x >= __fvw_w )); then break; fi
            __fvw_i=$(( __fvw_j * __fvw_h + __fvw_y + __fvw_t ))
            __fvw_s=''
            if (( __fvw_i < __fvw_n && __fvw_i >= 0 )); then
                if [[ -n $__fvw_fm ]]; then "$__fvw_fm" "$__fvw_i" "$(( __fvw_cw + __fvw_in ))"; __fvw_s=$RESULT; else __fvw_s=${__fvw_la[$__fvw_i]-}; fi
                __fvw_s=${__fvw_s:__fvw_sk:__fvw_cw}
            fi
            if (( __fvw_act && __fvw_i == __fvw_f )); then
                __fvw_c=$__fvw_c3 __fvw_ld[CursorX]=$(( __fvw_x + 1 )) __fvw_ld[CursorY]=$__fvw_y
            elif (( __fvw_i < __fvw_n )) && { { (( __fvw_isb )) && { (( __fvw_i == __fvw_f )) || [[ ${__fvw_ma[$__fvw_i]:-0} != 0 ]]; }; } \
                    || { (( ! __fvw_isb )) && fv.views._virt "$1" IsSelected "$__fvw_i"; }; }; then
                __fvw_c=$__fvw_c4
            else __fvw_c=$__fvw_c2; fi
            if (( ! __fvw_isb )) && [[ -z ${__FV_VW_LIVE[$1]-} ]]; then return 0; fi
            _fvw_x[__fvw_y * __fvw_nc + __fvw_j]=" $__fvw_s" _fvw_s[__fvw_y * __fvw_nc + __fvw_j]=$__fvw_c
        done
    done
    local IFS=' '   # (the join's separator: a blank, as in fv.views._lvDraw)
    if [[ ${_fvw_x[*]} != $__FV_VS_PNA ]]; then
        # (each row composed: per column its blank + text cut to the column
        # and the divider when it lies inside the row)
        for (( __fvw_y = FV_CLIP_Y1; __fvw_y < __fvw_y2; __fvw_y++ )); do
            __fvw_rt='' __fvw_ra=''
            for (( __fvw_j = 0; __fvw_j < __fvw_nc; __fvw_j++ )); do
                __fvw_x=$(( __fvw_j * __fvw_cw ))
                if (( __fvw_x >= __fvw_w )); then break; fi
                __fvw_k=$(( __fvw_cw - 1 ))
                if (( __fvw_x + __fvw_k > __fvw_w )); then __fvw_k=$(( __fvw_w - __fvw_x )); fi
                __fvw_s=${_fvw_x[__fvw_y * __fvw_nc + __fvw_j]}$__FV_VW_PAD __fvw_c=${_fvw_s[__fvw_y * __fvw_nc + __fvw_j]}
                __fvw_rt+=${__fvw_s:0:__fvw_k} __fvw_ra+=${__FV_VW_AT[$__fvw_c]:0:__fvw_k}
                if (( __fvw_x + __fvw_cw - 1 < __fvw_w )); then __fvw_rt+='│' __fvw_ra+=$__fvw_c5; fi
            done
            _fvw_t[__fvw_y]=$__fvw_rt _fvw_a[__fvw_y]=$__fvw_ra
        done
        fv.views.writeLines 0 0 _fvw_t _fvw_a || :
        return 0
    fi
    for (( __fvw_j = 0; __fvw_j < __fvw_nc; __fvw_j++ )); do
        __fvw_x=$(( __fvw_j * __fvw_cw ))
        if (( __fvw_x >= __fvw_w )); then break; fi
        __fvw_k=$(( __fvw_cw - 1 ))
        if (( __fvw_x + __fvw_k > __fvw_w )); then __fvw_k=$(( __fvw_w - __fvw_x )); fi
        _fvw_r=() _fvw_q=() _fvw_t=() _fvw_a=()
        for (( __fvw_y = FV_CLIP_Y1; __fvw_y < __fvw_y2; __fvw_y++ )); do
            _fvw_r[__fvw_y]=${_fvw_x[__fvw_y * __fvw_nc + __fvw_j]} _fvw_q[__fvw_y]=${_fvw_s[__fvw_y * __fvw_nc + __fvw_j]}
            _fvw_t[__fvw_y]='│' _fvw_a[__fvw_y]=$__fvw_c5
        done
        fv.views.writeRows "$__fvw_x" 0 "$__fvw_k" _fvw_r _fvw_q || :
        if (( __fvw_x + __fvw_cw - 1 < __fvw_w )); then fv.views.writeLines "$(( __fvw_x + __fvw_cw - 1 ))" 0 _fvw_t _fvw_a || :; fi
    done
}

# TListViewer.IsSelected ITEM (func; rc 0 = yes) — FV: the focused item;
# besides, D26: an item whose Marks entry is set (not '' or 0)
fv.views._lvIsSelected() {
    local -n __fvw_ld=${1}_data
    local __fvw_m=${__fvw_ld[Marks]-}
    if [ "${2-}" = "${__fvw_ld[Focused]:-0}" ]; then return 0; fi
    if [[ -z ${2-} || $2 == *[!0123456789]* || ${#2} -gt 9 ]] || ! fv.views._lvName "$__fvw_m"; then return 1; fi
    local -n __fvw_ma=$__fvw_m
    [[ ${__fvw_ma[$(( 10#$2 ))]:-0} != 0 ]]
}

# fv.views._lvRows V A B — rule 4: the rows that show the items A and B
# (TopItem as it is) repainted with Draw's body as drawPart's painter — one
# drawPart over both when they are the same row or neighbours, else one
# each; an item out of the page draws nothing. A Draw of yours: drawView
fv.views._lvRows() {
    local -n __fvw_rd=${1}_data
    local __fvw_t=${__fvw_rd[TopItem]:-0} __fvw_h=${__fvw_rd[SizeY]:-0} __fvw_c=${__fvw_rd[NumCols]:-1} __fvw_a=-1 __fvw_b=-1 __fvw_o=${1}_class
    __fvw_o="${!__fvw_o-}_class_method_owner[Draw]"
    if ! [ "${__FV_VW_IMPL[${!__fvw_o-}.Draw]-}" = fv.views._lvDraw ]; then fv.views._drawView "$1"; return 0; fi
    if (( __fvw_h < 1 )); then return 0; fi
    if (( $2 >= __fvw_t && $2 < __fvw_t + __fvw_h * __fvw_c )); then __fvw_a=$(( ($2 - __fvw_t) % __fvw_h )); fi
    if (( $3 >= __fvw_t && $3 < __fvw_t + __fvw_h * __fvw_c )); then __fvw_b=$(( ($3 - __fvw_t) % __fvw_h )); fi
    if (( __fvw_a < 0 )); then __fvw_a=$__fvw_b; elif (( __fvw_b < 0 )); then __fvw_b=$__fvw_a; fi
    if (( __fvw_a < 0 )); then return 0; fi
    if (( __fvw_a > __fvw_b )); then __fvw_c=$__fvw_a __fvw_a=$__fvw_b __fvw_b=$__fvw_c; fi
    if (( __fvw_b - __fvw_a <= 1 )); then fv.views.drawPart "$1" fv.views._lvDraw "$__fvw_a" "$(( __fvw_b + 1 ))" || :; return 0; fi
    fv.views.drawPart "$1" fv.views._lvDraw "$__fvw_a" "$(( __fvw_a + 1 ))" || :
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    fv.views.drawPart "$1" fv.views._lvDraw "$__fvw_b" "$(( __fvw_b + 1 ))" || :
}

# TListViewer.FocusItem ITEM — FPC 2025: Focused := ITEM; the top item moved
# so that it shows (one column: ITEM the top or the bottom row; several: its
# column the first or the last) through SetTopItem; then drawn by rule 4:
# TopItem kept -> only the rows of the old and the new focused item
# (fv.views._lvRows: one drawPart for neighbours), moved -> the whole list
fv.views._lvFocusItem() {
    local -n __fvw_ld=${1}_data
    local __fvw_i=${2-} __fvw_o=${__fvw_ld[Focused]:-0} __fvw_t=${__fvw_ld[TopItem]:-0} __fvw_h=${__fvw_ld[SizeY]:-0} __fvw_c=${__fvw_ld[NumCols]:-1} __fvw_nt
    if [[ -z ${__fvw_i#-} || ${__fvw_i#-} == *[!0123456789]* || ${#__fvw_i} -gt 10 ]]; then return 0; fi
    if [[ $__fvw_i == -* ]]; then __fvw_i=$(( -10#${__fvw_i#-} )); else __fvw_i=$(( 10#$__fvw_i )); fi
    if (( __fvw_h < 1 )); then __fvw_h=1; fi
    __fvw_ld[Focused]=$__fvw_i __fvw_nt=$__fvw_t
    if (( __fvw_i < __fvw_t )); then
        if (( __fvw_c == 1 )); then __fvw_nt=$__fvw_i; else __fvw_nt=$(( __fvw_i - __fvw_i % __fvw_h )); fi
    elif (( __fvw_i >= __fvw_t + __fvw_h * __fvw_c )); then
        if (( __fvw_c == 1 )); then __fvw_nt=$(( __fvw_i - __fvw_h + 1 )); else __fvw_nt=$(( __fvw_i - __fvw_i % __fvw_h - __fvw_h * (__fvw_c - 1) )); fi
    fi
    if (( __fvw_nt != __fvw_t )); then fv.views._lvSetTop "$1" "$__fvw_nt"; fi
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    if (( ${__fvw_ld[TopItem]:-0} != __fvw_t )); then fv.views._drawView "$1"; return 0; fi
    fv.views._lvRows "$1" "$__fvw_o" "$__fvw_i"
}
# fv.views._lvFocusNum V I — FV FocusItemNum: I kept in 0 .. Range-1, then
# FocusItem (virtual) unless the list is empty
fv.views._lvFocusNum() {
    local -n __fvw_ld=${1}_data
    local __fvw_i=$2 __fvw_n=${__fvw_ld[Range]:-0}
    if (( __fvw_i < 0 )); then __fvw_i=0; elif (( __fvw_i >= __fvw_n && __fvw_n > 0 )); then __fvw_i=$(( __fvw_n - 1 )); fi
    if (( __fvw_n != 0 )); then fv.views._virt "$1" FocusItem "$__fvw_i" || :; fi
}

# fv.views._lvSetTop V ITEM — FPC 2025 SetTopItem: the range set again when
# SizeY changed since (its bar's steps follow), ITEM kept within the bar's Max
# and 0 .. Range-1, TopItem := ITEM, the bar moved to it (fv.views._lvBar).
# Nothing drawn
fv.views._lvSetTop() {
    local -n __fvw_ld=${1}_data
    local __fvw_i=$2 __fvw_b=${__fvw_ld[VScrollBar]-}
    if (( ${__fvw_ld[SizeY]:-0} != ${__FV_VW_LY[$1]:-0} )); then fv.views._lvSetRange "$1" "${__fvw_ld[Range]:-0}"; fi
    if [[ -n $__fvw_b && -z ${__FV_VW_SB[$__fvw_b]-} ]]; then __fvw_b=''; fi
    if [[ -n $__fvw_b ]]; then
        local -n __fvw_bd=${__fvw_b}_data
        if (( __fvw_i > ${__fvw_bd[Max]:-0} )); then __fvw_i=${__fvw_bd[Max]:-0}; fi
    fi
    if (( __fvw_i >= ${__fvw_ld[Range]:-0} )); then __fvw_i=$(( ${__fvw_ld[Range]:-0} - 1 )); fi
    if (( __fvw_i < 0 )); then __fvw_i=0; fi
    __fvw_ld[TopItem]=$__fvw_i
    if [[ -n $__fvw_b ]] && (( ${__fvw_bd[Value]:-0} != __fvw_i )); then
        fv.views._lvBar "$1" "$__fvw_b" "$__fvw_i" "${__fvw_bd[Min]:-0}" "${__fvw_bd[Max]:-0}"
    fi
}
# fv.views._lvBar V B VALUE MIN MAX — the list moves its own bar (P3-4, the
# direct link): SetParams with the bar's steps; while it runs, the list is
# left out of the bar's cmScrollBarChanged broadcast (__FV_VW_QX) — only when
# the list's HandleEvent is the built-in one (L7: a HandleEvent of yours gets
# FV's broadcast)
fv.views._lvBar() {
    local -n __fvw_bd=${2}_data
    local __fvw_q=$__FV_VW_QX __fvw_o=${1}_class
    __fvw_o="${!__fvw_o-}_class_method_owner[HandleEvent]"
    if [ "${__FV_VW_IMPL[${!__fvw_o-}.HandleEvent]-}" = fv.views._lvEvent ]; then __FV_VW_QX=$1; fi
    fv.views._sbSet "$2" "$3" "$4" "$5" "${__fvw_bd[PgStep]:-1}" "${__fvw_bd[ArStep]:-1}"
    __FV_VW_QX=$__fvw_q
}

# fv.views._lvSetRange V N — FPC 2025 SetRange: Range := N; SizeY changed
# since the last time -> the bar's steps (one column: SizeY-1 / 1, else
# SizeY*NumCols / SizeY); Focused past N -> 0; with a bar: its Max = the
# last top item that keeps the last item in view (several columns: the
# last NumCols columns), TopItem kept within it, SetParams(TopItem, 0,
# Max); without: TopItem within N (0 for an empty list, FV leaves -1).
# Nothing drawn here
fv.views._lvSetRange() {
    local -n __fvw_ld=${1}_data
    local __fvw_n=$2 __fvw_h=${__fvw_ld[SizeY]:-0} __fvw_c=${__fvw_ld[NumCols]:-1} __fvw_b=${__fvw_ld[VScrollBar]-} __fvw_x
    __fvw_ld[Range]=$__fvw_n
    if [[ -n $__fvw_b && -z ${__FV_VW_SB[$__fvw_b]-} ]]; then __fvw_b=''; fi
    if [[ -n $__fvw_b ]]; then local -n __fvw_bd=${__fvw_b}_data; fi
    if [[ -n $__fvw_b ]] && (( __fvw_h != ${__FV_VW_LY[$1]:-0} )); then
        if (( __fvw_c == 1 )); then __fvw_bd[PgStep]=$(( __fvw_h - 1 )) __fvw_bd[ArStep]=1
        else __fvw_bd[PgStep]=$(( __fvw_h * __fvw_c )) __fvw_bd[ArStep]=$__fvw_h; fi
    fi
    __FV_VW_LY[$1]=$__fvw_h
    if (( ${__fvw_ld[Focused]:-0} >= __fvw_n )); then __fvw_ld[Focused]=0; fi
    if [[ -n $__fvw_b ]]; then
        __fvw_x=$(( __fvw_n - __fvw_h ))
        if (( __fvw_n - 1 < __fvw_x )); then __fvw_x=$(( __fvw_n - 1 )); fi
        if (( __fvw_h > 0 && __fvw_c > 1 )); then
            __fvw_x=$(( __fvw_n / __fvw_h * __fvw_h ))
            if (( __fvw_x == __fvw_n )); then __fvw_x=$(( __fvw_x - __fvw_h )); fi
            __fvw_x=$(( __fvw_x - (__fvw_c - 1) * __fvw_h ))
        fi
        if (( __fvw_x < 0 )); then __fvw_x=0; fi
        if (( ${__fvw_ld[TopItem]:-0} > __fvw_x )); then __fvw_ld[TopItem]=$__fvw_x; fi
        fv.views._lvBar "$1" "$__fvw_b" "${__fvw_ld[TopItem]:-0}" 0 "$__fvw_x"
    elif (( ${__fvw_ld[TopItem]:-0} >= __fvw_n )); then
        __fvw_x=$(( __fvw_n - 1 ))
        if (( __fvw_x < 0 )); then __fvw_x=0; fi
        __fvw_ld[TopItem]=$__fvw_x
    fi
}

# TListViewer.SelectItem ITEM — FV: the cmListItemSelected broadcast to the
# owner (FV_EV_INFO = the list); first, D26: with Marks set, ITEM's mark
# toggled (1 / unset) and its row redrawn (rule 4) — unless the built-in
# key handler (Space / Ins) asked for the item (its __fvw_lvsk = V:ITEM): its
# FocusItem repaints that row next, once (__fvw_lvsk = 1 tells it)
fv.views._lvSelectItem() {
    local -n __fvw_ld=${1}_data
    local __fvw_m=${__fvw_ld[Marks]-} __fvw_i=${2-} __fvw_o=${__fvw_ld[Owner]-}
    if [[ -n $__fvw_i && $__fvw_i != *[!0123456789]* && ${#__fvw_i} -le 9 ]] && fv.views._lvName "$__fvw_m"; then
        local -n __fvw_ma=$__fvw_m
        __fvw_i=$(( 10#$__fvw_i ))
        if [[ ${__fvw_ma[$__fvw_i]:-0} != 0 ]]; then unset '__fvw_ma[$__fvw_i]'; else __fvw_ma[$__fvw_i]=1; fi
        if [ "${__fvw_lvsk-}" = "$1:$__fvw_i" ]; then __fvw_lvsk=1; else fv.views._lvRows "$1" "$__fvw_i" "$__fvw_i"; fi
    fi
    if [[ -n $__fvw_o && -n ${__FV_VW_LIVE[$1]-} && -n ${__FV_VW_LIVE[$__fvw_o]-} ]]; then fv.views._message "$__fvw_o" evBroadcast cmListItemSelected "$1" || :; fi
    return 0
}

# TListViewer.SetState BIT ENABLE — FV: TView's; then for sfSelected,
# sfActive or sfVisible the list drawn — P3-12: only what changes (sfVisible
# draws in TView's body; sfSelected / sfActive change only the focused row's
# colour, redrawn when "selected and active" changed) — and its bars shown
# when the list is active and visible, hidden otherwise (FV ShowSBar)
fv.views._lvSetState() {
    local -n __fvw_ld=${1}_data
    local __fvw_a=$(( (${__fvw_ld[State]:-0} & (FV_SF_SELECTED | FV_SF_ACTIVE)) == (FV_SF_SELECTED | FV_SF_ACTIVE) ))
    fv.views._viewSetState "$@"
    if (( ! ($2 & (FV_SF_SELECTED | FV_SF_ACTIVE | FV_SF_VISIBLE)) )) || [[ -z ${__FV_VW_LIVE[$1]-} ]]; then return 0; fi
    if (( ($2 & (FV_SF_SELECTED | FV_SF_ACTIVE)) && ${__fvw_ld[Range]:-0} > 0 \
          && __fvw_a != ((${__fvw_ld[State]:-0} & (FV_SF_SELECTED | FV_SF_ACTIVE)) == (FV_SF_SELECTED | FV_SF_ACTIVE)) )); then
        fv.views._lvRows "$1" "${__fvw_ld[Focused]:-0}" "${__fvw_ld[Focused]:-0}"
    fi
    fv.views._lvShowBar "$1" "${__fvw_ld[HScrollBar]-}"
    fv.views._lvShowBar "$1" "${__fvw_ld[VScrollBar]-}"
    return 0
}
fv.views._lvShowBar() {   # V B (FV ShowSBar)
    if [[ -z $2 || -z ${__FV_VW_SB[$2]-} || -z ${__FV_VW_LIVE[$1]-} ]]; then return 0; fi
    local -n __fvw_sd=${1}_data __fvw_bd=${2}_data
    if (( (${__fvw_sd[State]:-0} & (FV_SF_ACTIVE | FV_SF_VISIBLE)) == (FV_SF_ACTIVE | FV_SF_VISIBLE) )); then
        if (( ! (${__fvw_bd[State]:-0} & FV_SF_VISIBLE) )); then fv.views._virt "$2" SetState "$FV_SF_VISIBLE" 1 || :; fi
    elif (( ${__fvw_bd[State]:-0} & FV_SF_VISIBLE )); then fv.views._virt "$2" SetState "$FV_SF_VISIBLE" 0 || :; fi
}

# TListViewer.ChangeBounds AX AY BX BY — FV: TView's; then the bars' page
# steps: a horizontal one SizeX div NumCols, a vertical one SizeY * NumCols
fv.views._lvChangeBounds() {
    fv.views._viewChangeBounds "$@"
    [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
    local -n __fvw_ld=${1}_data
    local __fvw_b=${__fvw_ld[HScrollBar]-} __fvw_c=${__fvw_ld[NumCols]:-1}
    if (( __fvw_c < 1 )); then __fvw_c=1; fi
    if [[ -n $__fvw_b && -n ${__FV_VW_SB[$__fvw_b]-} ]]; then printf -v "${__fvw_b}_data[PgStep]" '%d' "$(( ${__fvw_ld[SizeX]:-0} / __fvw_c ))"; fi
    __fvw_b=${__fvw_ld[VScrollBar]-}
    if [[ -n $__fvw_b && -n ${__FV_VW_SB[$__fvw_b]-} ]]; then printf -v "${__fvw_b}_data[PgStep]" '%d' "$(( ${__fvw_ld[SizeY]:-0} * __fvw_c ))"; fi
    return 0
}

# TListViewer.HandleEvent — FV: TView's (a mouse-down focuses the list; it
# has ofFirstClick, so the click goes on), then keys (fv.views._lvKey), the
# bars' broadcasts (fv.views._lvBcast), the wheel (fv.views._lvWheel), a
# mouse-down (fv.views._lvMouse)
fv.views._lvEvent() {
    if [ "$FV_EV_WHAT" = evKeyDown ]; then fv.views._lvKey "$1"
    elif [ "$FV_EV_WHAT" = evMouseDown ]; then
        fv.views._viewEvent "$1"
        if [ "$FV_EV_WHAT" = evMouseDown ] && [[ -n ${__FV_VW_LIVE[$1]-} ]]; then fv.views._lvMouse "$1"; fi
    elif [ "$FV_EV_WHAT" = evBroadcast ]; then fv.views._lvBcast "$1"
    elif [ "$FV_EV_WHAT" = evMouseWheel ]; then fv.views._lvWheel "$1"; fi
    return 0
}
# fv.views._lvKey V — FV's keys (through CtrlToArrow): Space -> SelectItem
# (Focused) (virtual); Up / Down by one, PgUp / PgDn by SizeY * NumCols,
# Home / End, Left / Right by a column (NumCols > 1), Ctrl+PgUp / Ctrl+PgDn
# the page's first / last item; Ins with Marks set (D29, an addition):
# SelectItem(Focused) then down by one. The new item through FocusItemNum;
# with the built-in FocusItem the marked row is painted once: SelectItem
# leaves it to FocusItem (fv.views._lvSel; the old focused row is FocusItem's
# to repaint).
# handled. Other keys pass
fv.views._lvKey() {
    local -n __fvw_ld=${1}_data
    local __fvw_f=${__fvw_ld[Focused]:-0} __fvw_n=${__fvw_ld[Range]:-0} __fvw_h=${__fvw_ld[SizeY]:-0} __fvw_c=${__fvw_ld[NumCols]:-1} __fvw_i __fvw_lvsk=''
    if [ "$FV_EV_KEY" = kbChar ] && [ "$FV_EV_CHAR" = ' ' ] && (( __fvw_f < __fvw_n )); then
        fv.views._lvSel "$1"
        __fvw_i=$__fvw_f
    else
        case ${__FV_VW_C2A[${FV_EV_KEY:-kbNoKey}]-$FV_EV_KEY} in
            kbDown) __fvw_i=$(( __fvw_f + 1 )) ;;
            kbUp) __fvw_i=$(( __fvw_f - 1 )) ;;
            kbPgDn) __fvw_i=$(( __fvw_f + __fvw_h * __fvw_c )) ;;
            kbPgUp) __fvw_i=$(( __fvw_f - __fvw_h * __fvw_c )) ;;
            kbHome) __fvw_i=0 ;;
            kbEnd) __fvw_i=$(( __fvw_n - 1 )) ;;
            kbRight) if (( __fvw_c > 1 )); then __fvw_i=$(( __fvw_f + __fvw_h )); else return 0; fi ;;
            kbLeft) if (( __fvw_c > 1 )); then __fvw_i=$(( __fvw_f - __fvw_h )); else return 0; fi ;;
            kbCtrlPgDn) __fvw_i=$(( ${__fvw_ld[TopItem]:-0} + __fvw_h * __fvw_c - 1 )) ;;
            kbCtrlPgUp) __fvw_i=${__fvw_ld[TopItem]:-0} ;;
            kbIns)
                if [[ -z ${__fvw_ld[Marks]-} ]] || (( __fvw_f >= __fvw_n )); then return 0; fi
                fv.views._lvSel "$1"
                __fvw_i=$(( __fvw_f + 1 )) ;;
            *) return 0 ;;
        esac
    fi
    [[ -n ${__FV_VW_LIVE[$1]-} ]] && fv.views._lvFocusNum "$1" "$__fvw_i"
    FV_EV_WHAT=evNothing FV_EV_INFO=$1
}
# fv.views._lvSel V — _lvKey's SelectItem(Focused) (virtual): with the
# built-in FocusItem, _lvKey's __fvw_lvsk = V:Focused (the built-in SelectItem
# then leaves the row's paint to FocusItem, which repaints the old focused
# row); a handler that moved the focus meanwhile: the row painted here
fv.views._lvSel() {
    local __fvw_o=${1}_class
    __fvw_o="${!__fvw_o-}_class_method_owner[FocusItem]"
    if [ "${__FV_VW_IMPL[${!__fvw_o-}.FocusItem]-}" = fv.views._lvFocusItem ]; then __fvw_lvsk=$1:$__fvw_f; fi
    fv.views._virt "$1" SelectItem "$__fvw_f" || :
    if [ "$__fvw_lvsk" = 1 ] && [[ -n ${__FV_VW_LIVE[$1]-} ]] && (( ${__fvw_ld[Focused]:-0} != __fvw_f )); then fv.views._lvRows "$1" "$__fvw_f" "$__fvw_f"; fi
    __fvw_lvsk=''
}
# fv.views._lvBcast V — FV (a selectable list): cmScrollBarClicked from one
# of its bars -> Select; cmScrollBarChanged from its vertical bar -> ScrollTo
# the bar's value (fv.views._lvScroll), from its horizontal bar -> drawn.
# Not handled (FV)
fv.views._lvBcast() {
    local -n __fvw_ld=${1}_data
    if (( ! (${__fvw_ld[Options]:-0} & FV_OF_SELECTABLE) )) || [[ -z $FV_EV_INFO ]]; then return 0; fi
    if [ "$FV_EV_COMMAND" = cmScrollBarClicked ]; then
        if [ "$FV_EV_INFO" = "${__fvw_ld[HScrollBar]-}" ] || [ "$FV_EV_INFO" = "${__fvw_ld[VScrollBar]-}" ]; then fv.views._select "$1"; fi
    elif [ "$FV_EV_COMMAND" = cmScrollBarChanged ]; then
        if [ "$FV_EV_INFO" = "${__fvw_ld[VScrollBar]-}" ]; then
            if [[ -n ${__FV_VW_SB[$FV_EV_INFO]-} ]]; then
                local -n __fvw_bd=${FV_EV_INFO}_data
                fv.views._lvScroll "$1" "${__fvw_bd[Value]:-0}"
            fi
        elif [ "$FV_EV_INFO" = "${__fvw_ld[HScrollBar]-}" ]; then fv.views._drawView "$1"; fi
    fi
    return 0
}
# fv.views._lvScroll V REQ — FV ScrollTo: SetTopItem(REQ), drawn (when
# TopItem changed: P3-12)
fv.views._lvScroll() {
    local -n __fvw_ld=${1}_data
    local __fvw_t=${__fvw_ld[TopItem]:-0}
    fv.views._lvSetTop "$1" "$2"
    if [[ -n ${__FV_VW_LIVE[$1]-} ]] && (( ${__fvw_ld[TopItem]:-0} != __fvw_t )); then fv.views._drawView "$1"; fi
}
# fv.views._lvWheel V — FV: the top item down (FV_EV_WHEEL 2) / up (1) by a
# column (SizeY) with several columns, else by 1 (a double wheel event: 4);
# handled
fv.views._lvWheel() {
    local -n __fvw_ld=${1}_data
    local __fvw_d=1
    if (( ${__fvw_ld[NumCols]:-1} > 1 )); then __fvw_d=${__fvw_ld[SizeY]:-1}; elif (( ${FV_EV_MOUSE_DOUBLE:-0} == 1 )); then __fvw_d=4; fi
    if (( FV_EV_WHEEL == 1 )); then __fvw_d=$(( -__fvw_d )); elif (( FV_EV_WHEEL != 2 )); then return 0; fi
    fv.views._lvScroll "$1" "$(( ${__fvw_ld[TopItem]:-0} + __fvw_d ))"
    FV_EV_WHAT=evNothing FV_EV_INFO=$1
}
# fv.views._lvMouse V — FV's mouse-down: the item under the mouse (row +
# SizeY * column + TopItem) focused (FocusItemNum), then while the button is
# held (moves coalesced, evMouseAuto: fv.views._track) the item under the
# mouse; outside the list every 4th evMouseAuto (FV MouseAutosToSkip) moves
# the focus one item (several columns: a column left / right, or to the
# column's first / last row). A double click's press (FV_EV_MOUSE_DOUBLE:
# FPC's release never has Double) is not tracked (FPC trunk: `If NOT
# Event.Double Then Repeat ... Until`): the item under it is focused and
# selected at once (SelectItem, virtual), the moves and the release left for
# the event loop. A key ends the tracking (fv.views._track); handled
fv.views._lvMouse() {
    local -n __fvw_ld=${1}_data
    local __fvw_h=${__fvw_ld[SizeY]:-0} __fvw_c=${__fvw_ld[NumCols]:-1} __fvw_w=${__fvw_ld[SizeX]:-0} __fvw_cw __fvw_oi=${__fvw_ld[Focused]:-0}
    local __fvw_ni __fvw_ct=0 __fvw_x __fvw_y __fvw_d=${FV_EV_MOUSE_DOUBLE:-0} __fvw_f
    if (( __fvw_c < 1 )); then __fvw_c=1; fi
    if (( __fvw_h < 1 )); then __fvw_h=1; fi
    __fvw_cw=$(( __fvw_w / __fvw_c + 1 ))
    __fvw_x=$(( FV_EV_MOUSE_X - __FV_VW_AX[$1] )) __fvw_y=$(( FV_EV_MOUSE_Y - __FV_VW_AY[$1] ))
    if (( __fvw_x >= 0 && __fvw_y >= 0 && __fvw_x < __fvw_w && __fvw_y < __fvw_h )); then __fvw_ni=$(( __fvw_y + __fvw_h * (__fvw_x / __fvw_cw) + ${__fvw_ld[TopItem]:-0} ))
    else __fvw_ni=$__fvw_oi; fi
    # (a release an earlier loop's drain met and never used is not this one's;
    # FV: after a double click's press no tracking, the item under it at once)
    __FV_VW_TRK=''
    while (( __fvw_d != 1 )); do
        if (( __fvw_ni != __fvw_oi )); then
            fv.views._lvFocusNum "$1" "$__fvw_ni"
            [[ -n ${__FV_VW_LIVE[$1]-} ]] || return 0
            __fvw_oi=${__fvw_ld[Focused]:-0}
        fi
        __fvw_x=$(( FV_EV_MOUSE_X - __FV_VW_AX[$1] )) __fvw_y=$(( FV_EV_MOUSE_Y - __FV_VW_AY[$1] ))
        if (( __fvw_x >= 0 && __fvw_y >= 0 && __fvw_x < __fvw_w && __fvw_y < __fvw_h )); then
            __fvw_ni=$(( __fvw_y + __fvw_h * (__fvw_x / __fvw_cw) + ${__fvw_ld[TopItem]:-0} ))
        else
            if [ "$FV_EV_WHAT" = evMouseAuto ]; then __fvw_ct=$(( __fvw_ct + 1 )); fi
            if (( __fvw_ct == 4 )); then
                __fvw_ct=0 __fvw_f=${__fvw_ld[Focused]:-0}
                if (( __fvw_c == 1 )); then
                    if (( __fvw_y < 0 )); then __fvw_ni=$(( __fvw_f - 1 )); fi
                    if (( __fvw_y >= __fvw_h )); then __fvw_ni=$(( __fvw_f + 1 )); fi
                else
                    if (( __fvw_x < 0 )); then __fvw_ni=$(( __fvw_f - __fvw_h )); fi
                    if (( __fvw_x >= __fvw_w )); then __fvw_ni=$(( __fvw_f + __fvw_h )); fi
                    if (( __fvw_y < 0 )); then __fvw_ni=$(( __fvw_f - __fvw_f % __fvw_h )); fi
                    if (( __fvw_y > __fvw_h )); then __fvw_ni=$(( __fvw_f - __fvw_f % __fvw_h + __fvw_h - 1 )); fi
                fi
            fi
        fi
        fv.views._track "$1" "$(( FV_EM_MOUSEMOVE | FV_EM_MOUSEAUTO ))" || break
    done
    if (( __fvw_oi != __fvw_ni )); then fv.views._lvFocusNum "$1" "$__fvw_ni"; fi
    if [[ -n ${__FV_VW_LIVE[$1]-} ]] && (( __fvw_d == 1 && ${__fvw_ld[Range]:-0} > ${__fvw_ld[Focused]:-0} )); then
        fv.views._virt "$1" SelectItem "${__fvw_ld[Focused]:-0}" || :
    fi
    FV_EV_WHAT=evNothing FV_EV_INFO=$1
}

# ---- the list's plain API -----------------------------------------------------
# Each keeps RESULT; rc 2 for a view that is not a TListViewer, a number that
# is not an integer, a wrong count.

# fv.views.listFocusItem LV I — FV FocusItemNum: I kept in 0 .. Range-1,
# then FocusItem (virtual; the built-in moves TopItem to show it and draws
# by rule 4) unless the list is empty
fv.views.listFocusItem() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._list "$1" listFocusItem || return
    local -a __fvw_v
    local __fvw_r=${RESULT-}
    if ! fv.views._ints "$2"; then fv.views._bad listFocusItem 'I must be an integer'; return; fi
    fv.views._lvFocusNum "$1" "${__fvw_v[0]}"
    RESULT=$__fvw_r
}
# fv.views.listSetRange LV N — FV SetRange (the items are List[0 .. N-1] or
# the formatter's), then the list drawn: after the caller changed its data
# (N >= 0)
fv.views.listSetRange() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._list "$1" listSetRange || return
    local -a __fvw_v
    local __fvw_r=${RESULT-}
    if ! fv.views._ints "$2" || (( __fvw_v[0] < 0 )); then fv.views._bad listSetRange 'N must be an integer >= 0'; return; fi
    fv.views._lvSetRange "$1" "${__fvw_v[0]}"
    if [[ -n ${__FV_VW_LIVE[$1]-} ]]; then fv.views._drawView "$1"; fi
    RESULT=$__fvw_r
}
# fv.views.listSetTopItem LV I — FV SetTopItem + DrawView (ScrollTo): the
# list drawn when its top item changed
fv.views.listSetTopItem() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._list "$1" listSetTopItem || return
    local -a __fvw_v
    local __fvw_r=${RESULT-}
    if ! fv.views._ints "$2"; then fv.views._bad listSetTopItem 'I must be an integer'; return; fi
    fv.views._lvScroll "$1" "${__fvw_v[0]}"
    RESULT=$__fvw_r
}
# fv.views.listDrawItem LV I — item I's row redrawn when it is on the page
# (rule 4: after the caller changed its text or its mark)
fv.views.listDrawItem() {
    if (( $# != 2 )); then fv.views._bad "${FUNCNAME#fv.views.}" 'wrong argument count'; return; fi
    fv.views._list "$1" listDrawItem || return
    local -a __fvw_v
    local __fvw_r=${RESULT-}
    if ! fv.views._ints "$2"; then fv.views._bad listDrawItem 'I must be an integer'; return; fi
    fv.views._lvRows "$1" "${__fvw_v[0]}" "${__fvw_v[0]}"
    RESULT=$__fvw_r
}
