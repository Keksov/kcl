#!/usr/bin/env bash
# image_sim.sh — the simulated image start of kklass/docs/dev/IMAGE_PLAN.md §5.2
# (the subshell form, no prior set) as a reusable test helper. Not a test file:
# the ktests runner picks up NNN_*.sh only. Image stage I1a; I1b runs it over
# every unit, and I2a's writer reuses its logic (kclt_sim_state is the one
# state dump).
#
# Use, in a FRESH hermetic bash (no unit loaded yet: no prior set):
#
#     source "$KBOOL_ROOT/kbool.sh"
#     source "$KCL_DIR/tests/image_sim.sh"
#     kclt_sim UNIT...        # rc 0 and the one line "sim:ok", else rc 1 and
#                             # "sim:..." lines, the first naming the problem
#
# The caller's shell options do not matter: every function here runs with
# `local -; set +eu` and nocasematch off for its own code (restored on
# return); the load and the hooks run with the caller's nounset and
# nocasematch (errexit never: a failure is reported, not fatal).
#
# kclt_sim UNIT... —
#   1. records the state before the load: every variable (`declare -p`) and
#      the shell state (traps, aliases, umask, `set +o`, `shopt -p`);
#   2. `kk.uses UNIT...`; the shell state must be unchanged ("sim:shell-state
#      trap|alias|umask|options": an image never holds them, plan §4 / §6.3);
#      the end-of-load state is dumped (kclt_sim_state);
#   3. in a subshell (this shell untouched): every hook VAR of the load (the
#      keys of __KK_SETTINGS_VARS — every unit of the load, there is no prior
#      set) is put back to its state before the load (unset — a nameref by
#      `unset -n` —, or its recorded value and attributes); every hook of
#      __KK_UNIT_SETTINGS runs in THAT order (the order the kk.settings
#      calls ran, which an image start replays too; NOT __KK_UNIT_ORDER,
#      where tfind (registered first, it loads tutil) comes before tutil,
#      whose hook declares the registry tfind's hook appends to (I1b critic
#      M2); the state is dumped again and
#      must equal the end-of-load dump ("sim:diff KIND:NAME" names the first
#      differing variable / function / attribute / shell-state line, with
#      both texts);
#   4. the same subshell runs every hook a second time and dumps again: still
#      equal, or "sim:rerun KIND:NAME" (a hook must be safe to run twice — an
#      append without the check for its entry shows here);
#   5. statically, from the bash-normalised text (`declare -f`) of each hook
#      and of the functions it calls (transitively, but not into kkore's /
#      kklass's kk.* functions), the variables it assigns — NAME=, NAME+=,
#      NAME[K]= (not a temporary NAME=V in front of a command), declare -g,
#      export, readonly, unset, printf -v NAME, read's / mapfile's name
#      operands, for NAME in, : "${NAME:=...}", a call of kk.localeDefault
#      (LC_CTYPE, I1b critic L1) — minus the locals of the call
#      path must be listed by its unit: else "sim:unlisted FN VAR". A
#      heuristic over the printed text (statements cut at ; & | ( ) { } and
#      quotes): an arithmetic `(( x = 1 ))`, an eval'd or indirect write
#      (printf -v "$1", a nameref, a call through "$f") is not seen — step 6
#      catches those;
#   6. a second subshell (the dynamic probe): every PUBLIC variable the load
#      created (not `_*`, not KCLT_SIM_SKIP, not readonly) that no hook lists
#      is unset, the hooks run one by one in load order, and a variable that
#      comes back is "sim:unlisted-dyn FN VAR" (FN: the hook after which it
#      reappeared).
# Other lines: "sim:load-rc N" (the load failed), "sim:hook-rc FN N",
# "sim:readonly VAR" (a hook VAR is readonly: it cannot be put back; steps 3-5
# are skipped).
# A pid-derived hook VAR (fv.views' __FV_VW_OWNER) compares equal only in
# pairs: its end-of-load value is the loading shell's $BASHPID AND its
# simulated value is the subshell's $BASHPID (then the simulated value is set
# back to the loader's pid before the dump); a constant that happens to equal
# a pid compares as it is.
#
# kclt_sim_state FILE — THE STATE DUMP, fork-free, under LC_ALL=C (the quoting
# `declare -p` picks depends on the locale): sections
#   @@V  every variable with its attributes (`declare -p` of the names
#        `compgen -v` lists, filtered); the caller's IFS and LC_ALL first
#        (taken before this function's own locals shadow them);
#   @@F  every function (`declare -f`);
#   @@X  the function attributes (`declare -Fx`, `declare -Ft`: exported,
#        traced);
#   @@S  the shell state: `trap -p`, `alias -p`, `umask`.
# NOT COMPARED (KCLT_SIM_SKIP; a statement about what this harness compares,
# not about the image's never-holds list of plan §4):
#   * bash's own dynamic variables — _ BASHPID BASH_ARGC BASH_ARGV BASH_ARGV0
#     BASH_COMMAND BASH_LINENO BASH_MONOSECONDS BASH_REMATCH BASH_SOURCE
#     BASH_SUBSHELL BASH_TRAPSIG
#     EPOCHREALTIME EPOCHSECONDS FUNCNAME HISTCMD LINENO PIPESTATUS RANDOM
#     SECONDS SRANDOM, and COLUMNS LINES (checkwinsize) — they change on their
#     own, per call, per subshell, per command;
#   * RESULT, kbool's return register (scratch by contract);
#   * __kk_ft, kklass's pid / fd state of its `declare -f` reader (plan §4:
#     never image state): class builds open it during the load, kklass's
#     hook drops it, and kk._fn_text opens it again lazily in any process
#     whose pid is not its first element — so an image start, which has none,
#     behaves the same (image I1b);
#   * this helper's own names: variables __ks_* / KCLT_SIM_*, functions
#     kclt_sim*.
# The dump compares two states of ONE process (and its subshells): bash
# prints an associative array in its hash order, which is the same there but
# may differ between two processes that built the same table differently — a
# canonical (sorted) order for cross-process comparisons is image stage I2b's
# (chained images, a fresh-process simulation), not this helper's.
#
# The dump goes through temp files, never a pipe (IMAGE_PLAN M12), and reads
# them back with `read -N` (mapfile reads 36 000 lines in ~2 s on the Windows
# runtimes, `read -N` the same file in ~20 ms); the record parser runs only to
# explain a mismatch. The scratch folder is KCLT_SIM_DIR, else
# KCLT_TMP/sim.PID (never /tmp). Forks: the two subshells and one mkdir.

KCLT_SIM_SKIP=" _ __kk_ft BASHPID BASH_MONOSECONDS BASH_TRAPSIG BASH_ARGC BASH_ARGV BASH_ARGV0 BASH_COMMAND BASH_LINENO BASH_REMATCH BASH_SOURCE BASH_SUBSHELL EPOCHREALTIME EPOCHSECONDS FUNCNAME HISTCMD LINENO PIPESTATUS RANDOM SECONDS SRANDOM COLUMNS LINES RESULT "

# kclt_sim_lines FILE — KCLT_SIM_L = FILE's lines (empty lines dropped): one
# `read -N` and a split in memory.
kclt_sim_lines() {
    local - __ks_z="" IFS=$'\n'
    set +eu -f
    read -r -N 268435456 __ks_z < "$1" || :
    KCLT_SIM_L=($__ks_z)
}

# kclt_sim_state FILE — the state dump (see the header).
kclt_sim_state() {
    # the caller's IFS and LC_ALL, before any local of this function
    declare -p IFS LC_ALL > "$1.pre" 2>/dev/null || :     # (LC_ALL unset: rc 1, also under a caller's set -e)
    local - __ks_nc=0
    set +eu
    if [[ $BASHOPTS == *nocasematch* ]]; then __ks_nc=1; shopt -u nocasematch; fi
    # (in a function of its own: the locale its `local LC_ALL` leaves may
    # warn on stderr at its return)
    kclt_sim__dump "$1" 2>/dev/null
    if (( __ks_nc )); then shopt -s nocasematch; fi
    return 0
}
kclt_sim__dump() {
    local LC_ALL=C IFS=$'\n' __ks_f=$1 __ks_z="" __ks_x
    local -a __ks_v=() __ks_n=() __ks_fn=()
    set -f
    compgen -v > "$__ks_f.raw"
    read -r -N 268435456 __ks_z < "$__ks_f.raw" || :
    __ks_v=($__ks_z)
    for __ks_x in "${__ks_v[@]}"; do
        [[ $KCLT_SIM_SKIP == *" $__ks_x "* || $__ks_x == __ks_* || $__ks_x == KCLT_SIM_* \
           || $__ks_x == IFS || $__ks_x == LC_ALL ]] && continue
        __ks_n+=("$__ks_x")
    done
    compgen -A function > "$__ks_f.raw"
    __ks_z=""
    read -r -N 268435456 __ks_z < "$__ks_f.raw" || :
    __ks_v=($__ks_z)
    for __ks_x in "${__ks_v[@]}"; do
        [[ $__ks_x == kclt_sim* ]] || __ks_fn+=("$__ks_x")
    done
    __ks_z=""
    read -r -N 268435456 __ks_z < "$__ks_f.pre" || :
    {
        printf '@@V\n%s' "$__ks_z"
        declare -p "${__ks_n[@]}"
        printf '@@F\n'
        if (( ${#__ks_fn[@]} )); then declare -f "${__ks_fn[@]}"; fi
        printf '@@X\n'
        declare -Fx
        declare -Ft
        printf '@@S\n'
        trap -p
        alias -p
        umask
    } > "$__ks_f"
}

# kclt_sim_cmp A B — rc 0 when the dumps A and B are equal; else rc 1 and
# KCLT_SIM_DIFF = "KIND:NAME" of the first differing record (A's order, then
# B's records A lacks; KIND V F X S) with both texts (newlines as |, cut to
# 300 chars); with KCLT_SIM_ALL non-empty, " KIND:NAME..." of every differing
# record (no texts). The equal case costs two reads.
kclt_sim_cmp() {
    local - __ks_nc=0 __ks_va="" __ks_vb="" __ks_r
    set +eu
    if [[ $BASHOPTS == *nocasematch* ]]; then __ks_nc=1; shopt -u nocasematch; fi
    KCLT_SIM_DIFF=""
    read -r -N 268435456 __ks_va < "$1" || :
    read -r -N 268435456 __ks_vb < "$2" || :
    if [[ $__ks_va == "$__ks_vb" ]]; then __ks_r=0; else kclt_sim__explain "$1" "$2"; __ks_r=1; fi
    if (( __ks_nc )); then shopt -s nocasematch; fi
    return "$__ks_r"
}

# kclt_sim__records FILE — KCLT_SIM_RK (record keys, in order) and
# KCLT_SIM_RT[KEY] (record text) of a dump
kclt_sim__records() {
    local __ks_x __ks_k="" __ks_t="" __ks_s="" __ks_n
    KCLT_SIM_RK=() KCLT_SIM_RT=()
    kclt_sim_lines "$1"
    for __ks_x in "${KCLT_SIM_L[@]}"; do
        if [[ $__ks_x == @@[VFXS] ]]; then
            [[ -z $__ks_k ]] || KCLT_SIM_RT[$__ks_k]=$__ks_t
            __ks_s=${__ks_x:2:1} __ks_k="" __ks_t=""
            continue
        fi
        __ks_n=""
        case $__ks_s in
            V) if [[ $__ks_x == 'declare -'* ]]; then __ks_n=${__ks_x#declare -* }; __ks_n=V:${__ks_n%%=*}; fi ;;
            F) if [[ $__ks_x == *' () ' && $__ks_x != [[:space:]]* ]]; then __ks_n=F:${__ks_x% () }; fi ;;
            *) __ks_n=$__ks_s:$__ks_x ;;
        esac
        if [[ -n $__ks_n ]]; then
            [[ -z $__ks_k ]] || KCLT_SIM_RT[$__ks_k]=$__ks_t
            __ks_k=$__ks_n __ks_t=""
            KCLT_SIM_RK+=("$__ks_k")
        fi
        __ks_t+=$__ks_x$'\n'
    done
    [[ -z $__ks_k ]] || KCLT_SIM_RT[$__ks_k]=$__ks_t
}
declare -gA KCLT_SIM_RT=()

kclt_sim__explain() {
    local __ks_i __ks_va __ks_vb
    local -a __ks_ord=()
    local -A __ks_ra=() __ks_rb=() __ks_in=()
    kclt_sim__records "$1"
    __ks_ord=("${KCLT_SIM_RK[@]}")
    for __ks_i in "${KCLT_SIM_RK[@]}"; do __ks_ra[$__ks_i]=${KCLT_SIM_RT[$__ks_i]}; __ks_in[$__ks_i]=1; done
    kclt_sim__records "$2"
    for __ks_i in "${KCLT_SIM_RK[@]}"; do
        __ks_rb[$__ks_i]=${KCLT_SIM_RT[$__ks_i]}
        [[ -n ${__ks_in[$__ks_i]-} ]] || __ks_ord+=("$__ks_i")
    done
    for __ks_i in "${__ks_ord[@]}"; do
        if [[ ${__ks_ra[$__ks_i]-<none>} != "${__ks_rb[$__ks_i]-<none>}" ]]; then
            if [[ -n ${KCLT_SIM_ALL-} ]]; then KCLT_SIM_DIFF+=" $__ks_i"; continue; fi
            __ks_va=${__ks_ra[$__ks_i]-<none>} __ks_vb=${__ks_rb[$__ks_i]-<none>}
            __ks_va=${__ks_va//$'\n'/|} __ks_vb=${__ks_vb//$'\n'/|}
            KCLT_SIM_DIFF="$__ks_i before=${__ks_va:0:300} after=${__ks_vb:0:300}"
            return 0
        fi
    done
    [[ -n $KCLT_SIM_DIFF ]] || KCLT_SIM_DIFF="(empty lines or record order only)"
}

# kclt_sim_targets FN [LOCALS] — KCLT_SIM_TGT += "VAR " for every variable FN
# and the functions it calls assign, outside the locals of the call path
# (step 5). A call = a word in command position naming a defined function
# (kk.* functions are not walked). Each function is walked once per call
# path (KCLT_SIM_SEEN guards recursion). Needs KCLT_SIM_FTMP (a temp file).
kclt_sim_targets() {
    local - IFS=$' \t\n' __ks_nc=0
    set +eu
    if [[ $BASHOPTS == *nocasematch* ]]; then __ks_nc=1; shopt -u nocasematch; fi
    kclt_sim__targets "$@"
    if (( __ks_nc )); then shopt -s nocasematch; fi
    return 0
}
kclt_sim__targets() {
    local __ks_fn=$1 __ks_loc=${2- } __ks_l __ks_s __ks_w __ks_v __ks_i __ks_na
    local -a __ks_ln=() __ks_ws=() __ks_calls=() __ks_set=()
    [[ $__ks_fn == : || $__ks_fn == kk.* || $KCLT_SIM_SEEN == *" $__ks_fn "* ]] && return 0
    KCLT_SIM_SEEN+="$__ks_fn "
    declare -f -- "$__ks_fn" > "$KCLT_SIM_FTMP" 2>/dev/null || return 0
    kclt_sim_lines "$KCLT_SIM_FTMP"; __ks_ln=("${KCLT_SIM_L[@]}")
    # the function's own locals first (bash scopes are per function)
    for __ks_l in "${__ks_ln[@]:2}"; do
        __ks_l=${__ks_l#"${__ks_l%%[![:space:]]*}"}
        kclt_sim_split "$__ks_l"
        for __ks_s in "${KCLT_SIM_ST[@]}"; do
            read -r -a __ks_ws <<<"$__ks_s"
            case ${__ks_ws[0]-} in
                local|typeset|declare)
                    [[ ${__ks_ws[0]} != local ]] && kclt_sim_isg "${__ks_ws[@]:1}" && continue
                    for __ks_w in "${__ks_ws[@]:1}"; do
                        [[ $__ks_w == -* ]] && continue
                        __ks_v=${__ks_w%%[=[]*}
                        [[ $__ks_v =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && __ks_loc+="$__ks_v "
                    done ;;
            esac
        done
    done
    for __ks_l in "${__ks_ln[@]:2}"; do
        __ks_l=${__ks_l#"${__ks_l%%[![:space:]]*}"}
        kclt_sim_split "$__ks_l"
        for __ks_s in "${KCLT_SIM_ST[@]}"; do
            read -r -a __ks_ws <<<"$__ks_s"
            (( ${#__ks_ws[@]} )) || continue
            __ks_set=() __ks_na=0
            # leading NAME=... words: assignments only when no command follows
            # (`IFS=, read ...` is a temporary environment for read)
            for __ks_w in "${__ks_ws[@]}"; do
                if [[ $__ks_w =~ ^([A-Za-z_][A-Za-z0-9_]*)(\[[^]]*\])?\+?= ]]; then
                    __ks_set+=("${BASH_REMATCH[1]}"); __ks_na=$(( __ks_na + 1 ))
                else
                    break
                fi
            done
            (( __ks_na < ${#__ks_ws[@]} )) && __ks_set=()
            # a builtin command that sets the variables it names
            __ks_w=${__ks_ws[__ks_na]-}
            __ks_ws=("${__ks_ws[@]:__ks_na+1}")
            case $__ks_w in
                declare|typeset)
                    if kclt_sim_isg "${__ks_ws[@]}"; then
                        for __ks_v in "${__ks_ws[@]}"; do
                            [[ $__ks_v == -* ]] && continue
                            __ks_v=${__ks_v%%[=[]*}
                            [[ $__ks_v =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && __ks_set+=("$__ks_v")
                        done
                    fi ;;
                export|readonly|unset)
                    for __ks_v in "${__ks_ws[@]}"; do
                        [[ $__ks_v == -* ]] && continue
                        __ks_v=${__ks_v%%[=[]*}
                        [[ $__ks_v =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && __ks_set+=("$__ks_v")
                    done ;;
                printf)
                    for (( __ks_i = 0; __ks_i < ${#__ks_ws[@]}; __ks_i++ )); do
                        __ks_v=${__ks_ws[__ks_i]}
                        if [[ $__ks_v == -v ]]; then __ks_v=${__ks_ws[__ks_i+1]-}
                        elif [[ $__ks_v == -v?* ]]; then __ks_v=${__ks_v#-v}
                        else continue; fi
                        __ks_v=${__ks_v%%[[]*}
                        [[ $__ks_v =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && __ks_set+=("$__ks_v")
                        break
                    done ;;
                read)
                    # options with an argument: -a (an array NAME) -d -i -n -N -p -t -u
                    for (( __ks_i = 0; __ks_i < ${#__ks_ws[@]}; __ks_i++ )); do
                        __ks_v=${__ks_ws[__ks_i]}
                        [[ $__ks_v == [\<\>]* || $__ks_v == [0-9][\<\>]* ]] && break
                        if [[ $__ks_v == -* ]]; then
                            if [[ $__ks_v == -*a ]]; then __ks_v=${__ks_ws[__ks_i+1]-}; __ks_i=$(( __ks_i + 1 ))
                                [[ $__ks_v =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && __ks_set+=("$__ks_v")
                            elif [[ $__ks_v == -*[dinNptu] ]]; then __ks_i=$(( __ks_i + 1 )); fi
                            continue
                        fi
                        [[ $__ks_v =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && __ks_set+=("$__ks_v")
                    done ;;
                mapfile|readarray)
                    __ks_na=MAPFILE
                    for (( __ks_i = 0; __ks_i < ${#__ks_ws[@]}; __ks_i++ )); do
                        __ks_v=${__ks_ws[__ks_i]}
                        [[ $__ks_v == [\<\>]* || $__ks_v == [0-9][\<\>]* ]] && break
                        if [[ $__ks_v == -* ]]; then
                            [[ $__ks_v == -*[dnOsuCc] ]] && __ks_i=$(( __ks_i + 1 ))
                            continue
                        fi
                        __ks_na=$__ks_v; break
                    done
                    [[ $__ks_na =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && __ks_set+=("$__ks_na") ;;
                for)
                    __ks_v=${__ks_ws[0]-}
                    [[ $__ks_v =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && __ks_set+=("$__ks_v") ;;
                kk.localeDefault)
                    # kkore's locale default exports LC_CTYPE (I1b critic L1)
                    __ks_set+=(LC_CTYPE) ;;
                *)
                    if [[ -n $__ks_w ]] && declare -F -- "$__ks_w" >/dev/null 2>&1; then __ks_calls+=("$__ks_w"); fi ;;
            esac
            # ${NAME:=...} / ${NAME=...} anywhere in the statement
            __ks_v=$__ks_s
            while [[ $__ks_v =~ \$\{([A-Za-z_][A-Za-z0-9_]*):?=(.*) ]]; do
                __ks_set+=("${BASH_REMATCH[1]}")
                __ks_v=${BASH_REMATCH[2]}
            done
            for __ks_v in "${__ks_set[@]}"; do
                [[ $__ks_loc == *" $__ks_v "* || $KCLT_SIM_TGT == *" $__ks_v "* ]] || KCLT_SIM_TGT+="$__ks_v "
            done
        done
    done
    for __ks_w in "${__ks_calls[@]}"; do
        kclt_sim__targets "$__ks_w" "$__ks_loc"
    done
    KCLT_SIM_SEEN=${KCLT_SIM_SEEN/" $__ks_fn "/" "}
    return 0
}

# kclt_sim_isg WORD... — rc 0 when an option word (-...) holds g (declare -g).
kclt_sim_isg() {
    local __ks_o
    for __ks_o in "$@"; do
        [[ $__ks_o == -* && $__ks_o != -- && $__ks_o == *g* ]] && return 0
    done
    return 1
}

# kclt_sim_split LINE — KCLT_SIM_ST: LINE cut into simple statements at
# ; & | ( ) { } outside quotes, ${...} and $(...); the reserved words that
# start a command list dropped (then do else elif if while until ! time),
# test commands ([[ ]], (( ))) and fi / done / esac skipped. Good enough for
# `declare -f` text, which puts one command per line.
kclt_sim_split() {
    local - __ks_t=$1 __ks_c __ks_cur="" __ks_q="" __ks_i __ks_n=${#1} __ks_o __ks_e __ks_j __ks_lv
    local -a __ks_r=()
    set +eu
    KCLT_SIM_ST=()
    for (( __ks_i = 0; __ks_i < __ks_n; __ks_i++ )); do
        __ks_c=${__ks_t:__ks_i:1}
        if [[ -n $__ks_q ]]; then
            __ks_cur+=$__ks_c
            if [[ $__ks_c == '\' && $__ks_q == '"' ]]; then __ks_cur+=${__ks_t:__ks_i+1:1}; __ks_i=$(( __ks_i + 1 )); continue; fi
            [[ $__ks_c == "$__ks_q" ]] && __ks_q=""
            continue
        fi
        case $__ks_c in
            \"|\') __ks_q=$__ks_c; __ks_cur+=$__ks_c ;;
            '\') __ks_cur+=$__ks_c${__ks_t:__ks_i+1:1}; __ks_i=$(( __ks_i + 1 )) ;;
            '$')
                # ${...} and $(...) stay whole (nested braces / parens counted)
                if [[ ${__ks_t:__ks_i+1:1} == [\{\(] ]]; then
                    __ks_o=${__ks_t:__ks_i+1:1} __ks_lv=0
                    if [[ $__ks_o == '{' ]]; then __ks_e='}'; else __ks_e=')'; fi
                    for (( __ks_j = __ks_i + 1; __ks_j < __ks_n; __ks_j++ )); do
                        if [[ ${__ks_t:__ks_j:1} == "$__ks_o" ]]; then __ks_lv=$(( __ks_lv + 1 )); fi
                        if [[ ${__ks_t:__ks_j:1} == "$__ks_e" ]]; then
                            __ks_lv=$(( __ks_lv - 1 ))
                            if (( __ks_lv == 0 )); then break; fi
                        fi
                    done
                    __ks_cur+=${__ks_t:__ks_i:__ks_j-__ks_i+1}
                    __ks_i=$__ks_j
                else
                    __ks_cur+=$__ks_c
                fi ;;
            ';'|'&'|'|'|'('|')'|'{'|'}')
                [[ -n ${__ks_cur//[[:space:]]/} ]] && KCLT_SIM_ST+=("$__ks_cur")
                __ks_cur="" ;;
            *) __ks_cur+=$__ks_c ;;
        esac
    done
    [[ -n ${__ks_cur//[[:space:]]/} ]] && KCLT_SIM_ST+=("$__ks_cur")
    for __ks_cur in "${KCLT_SIM_ST[@]}"; do
        __ks_cur=${__ks_cur#"${__ks_cur%%[![:space:]]*}"}
        while [[ $__ks_cur =~ ^(then|do|else|elif|if|while|until|!|time)[[:space:]]+(.*)$ ]]; do __ks_cur=${BASH_REMATCH[2]}; done
        [[ $__ks_cur == '[['* || $__ks_cur == '(('* || $__ks_cur == fi || $__ks_cur == done || $__ks_cur == esac ]] && continue
        __ks_r+=("$__ks_cur")
    done
    KCLT_SIM_ST=("${__ks_r[@]}")
}

# kclt_sim__caller_on / _off — the caller's nounset and nocasematch for the
# load and the hooks (kclt_sim's __ks_cu / __ks_cn), and back to ours
kclt_sim__caller_on() {
    if (( __ks_cn )); then shopt -s nocasematch; fi
    if (( __ks_cu )); then set -u; fi
}
kclt_sim__caller_off() {
    set +u
    shopt -u nocasematch
}

# kclt_sim__shell FILE — the shell state the load must not change
kclt_sim__shell() {
    {
        printf '@trap\n'; trap -p
        printf '@alias\n'; alias -p
        printf '@umask\n'; umask
        printf '@options\n'; set +o; shopt -p
    } > "$1" 2>/dev/null
}

# kclt_sim__hooks [ONCE] — run every hook in load order (caller options);
# report a non-zero rc unless ONCE is "quiet"
kclt_sim__hooks() {
    local __ks_e __ks_fn __ks_h
    for __ks_e in "${__KK_UNIT_SETTINGS[@]}"; do
        __ks_fn=${__ks_e#*"$__KK_SEP"}
        [[ $__ks_fn == : ]] && continue
        kclt_sim__caller_on
        "$__ks_fn"; __ks_h=$?
        kclt_sim__caller_off
        if (( __ks_h != 0 )) && [[ ${1-} != quiet ]]; then echo "sim:hook-rc $__ks_fn $__ks_h"; __ks_rc=1; fi
    done
}

# kclt_sim__pidpair — before a dump in the subshell: a hook VAR whose
# end-of-load value was the loader's pid (KCLT_SIM_PIDV) and whose value now
# is this subshell's pid gets the loader's pid back (the pair rule)
kclt_sim__pidpair() {
    local __ks_x
    for __ks_x in $KCLT_SIM_PIDV; do
        if [[ ${!__ks_x-} == "$BASHPID" ]]; then printf -v "$__ks_x" '%s' "$__ks_ppid"; fi
    done
}

kclt_sim() {
    local - __ks_d __ks_l __ks_n __ks_v __ks_e __ks_fn __ks_u __ks_flags __ks_at __ks_rc=0
    local __ks_cu=0 __ks_cn=0 __ks_ppid=$BASHPID __ks_x __ks_y __ks_z
    local -A __ks_pre=() __ks_new=()
    local -a __ks_a=() __ks_sh=()
    [[ $- == *u* ]] && __ks_cu=1
    [[ $BASHOPTS == *nocasematch* ]] && __ks_cn=1
    set +eu
    shopt -u nocasematch
    __ks_d=${KCLT_SIM_DIR:-${KCLT_TMP:-}/sim.$BASHPID}
    if [[ -z ${KCLT_SIM_DIR-} && -z ${KCLT_TMP-} ]]; then echo "sim:usage KCLT_SIM_DIR or KCLT_TMP must name a scratch folder"; return 2; fi
    mkdir -p "$__ks_d" || return 1
    # 1. the state before the load
    declare -p > "$__ks_d/pre.raw"
    kclt_sim_lines "$__ks_d/pre.raw"
    for __ks_l in "${KCLT_SIM_L[@]}"; do
        if [[ $__ks_l == 'declare -'* ]]; then
            __ks_n=${__ks_l#declare -* }
            __ks_n=${__ks_n%%=*}
            __ks_pre[$__ks_n]=$__ks_l
        elif [[ -n ${__ks_n-} ]]; then
            __ks_pre[$__ks_n]+=$'\n'$__ks_l
        fi
    done
    kclt_sim__caller_on; kclt_sim__shell "$__ks_d/sh0"; kclt_sim__caller_off
    # 2. the load; the shell state; the end-of-load state
    kclt_sim__caller_on
    kk.uses "$@"; __ks_rc=$?
    kclt_sim__caller_off
    if (( __ks_rc != 0 )); then echo "sim:load-rc $__ks_rc"; return 1; fi
    kclt_sim__caller_on; kclt_sim__shell "$__ks_d/sh1"; kclt_sim__caller_off
    read -r -N 268435456 __ks_x < "$__ks_d/sh0" || :
    read -r -N 268435456 __ks_y < "$__ks_d/sh1" || :
    if [[ $__ks_x != "$__ks_y" ]]; then
        __ks_z=""
        for __ks_v in trap alias umask options; do
            __ks_l=${__ks_x#*"@$__ks_v"$'\n'}; __ks_l=${__ks_l%%$'\n'@*}
            __ks_n=${__ks_y#*"@$__ks_v"$'\n'}; __ks_n=${__ks_n%%$'\n'@*}
            [[ $__ks_l == "$__ks_n" ]] || __ks_z+=" $__ks_v"
        done
        echo "sim:shell-state${__ks_z}"
        __ks_rc=1
    fi
    KCLT_SIM_PIDV=" "
    for __ks_v in "${!__KK_SETTINGS_VARS[@]}"; do
        __ks_at=""
        if declare -p "$__ks_v" >/dev/null 2>&1; then __ks_at=${!__ks_v@a}; fi
        [[ ! -R $__ks_v && $__ks_at != *[aA]* && ${!__ks_v-} == "$__ks_ppid" ]] && KCLT_SIM_PIDV+="$__ks_v "
    done
    kclt_sim_state "$__ks_d/end.d"
    # 3.-5. in a subshell
    (
        __ks_rc=0
        for __ks_v in "${!__KK_SETTINGS_VARS[@]}"; do
            __ks_at=""
            if declare -p "$__ks_v" >/dev/null 2>&1; then __ks_at=${!__ks_v@a}; fi
            if [[ ! -R $__ks_v && $__ks_at == *r* ]]; then echo "sim:readonly $__ks_v"; __ks_rc=1; continue; fi
            if [[ -R $__ks_v ]]; then unset -n "$__ks_v"; else unset -v "$__ks_v"; fi
            __ks_l=${__ks_pre[$__ks_v]-}
            [[ -n $__ks_l ]] || continue
            __ks_flags=${__ks_l#declare -}
            __ks_flags=${__ks_flags%% *}
            __ks_l=${__ks_l#declare -* }
            if [[ $__ks_flags == - ]]; then eval "declare -g $__ks_l"; else eval "declare -g$__ks_flags $__ks_l"; fi
        done
        # (a readonly hook VAR: no simulation is possible)
        if (( __ks_rc )); then exit "$__ks_rc"; fi
        kclt_sim__hooks
        kclt_sim__pidpair
        kclt_sim_state "$__ks_d/run1.d"
        if ! kclt_sim_cmp "$__ks_d/end.d" "$__ks_d/run1.d"; then echo "sim:diff $KCLT_SIM_DIFF"; __ks_rc=1; fi
        kclt_sim__hooks quiet
        kclt_sim__pidpair
        kclt_sim_state "$__ks_d/run2.d"
        if ! kclt_sim_cmp "$__ks_d/end.d" "$__ks_d/run2.d"; then echo "sim:rerun $KCLT_SIM_DIFF"; __ks_rc=1; fi
        KCLT_SIM_FTMP=$__ks_d/fn.raw
        for __ks_e in "${__KK_UNIT_SETTINGS[@]}"; do
            __ks_u=${__ks_e%%"$__KK_SEP"*} __ks_fn=${__ks_e#*"$__KK_SEP"}
            KCLT_SIM_TGT=" " KCLT_SIM_SEEN=" "
            kclt_sim_targets "$__ks_fn"
            for __ks_v in $KCLT_SIM_TGT; do
                [[ $__KK_SEP${__KK_SETTINGS_VARS[$__ks_v]-} == *"$__KK_SEP$__ks_u$__KK_SEP"* ]] && continue
                echo "sim:unlisted $__ks_fn $__ks_v"; __ks_rc=1
            done
        done
        exit "$__ks_rc"
    )
    __ks_rc=$(( __ks_rc | $? ))
    # 6. the dynamic probe, in a second subshell
    (
        __ks_rc=0
        compgen -v > "$__ks_d/names.raw"
        kclt_sim_lines "$__ks_d/names.raw"
        for __ks_v in "${KCLT_SIM_L[@]}"; do
            [[ $__ks_v == _* || -n ${__ks_pre[$__ks_v]+x} || -n ${__KK_SETTINGS_VARS[$__ks_v]+x} \
               || $KCLT_SIM_SKIP == *" $__ks_v "* || $__ks_v == KCLT_SIM_* ]] && continue
            __ks_at=${!__ks_v@a}
            [[ $__ks_at == *r* ]] && continue
            if [[ -R $__ks_v ]]; then unset -n "$__ks_v"; else unset -v "$__ks_v"; fi
            __ks_new[$__ks_v]=1
        done
        for __ks_e in "${__KK_UNIT_SETTINGS[@]}"; do
            __ks_fn=${__ks_e#*"$__KK_SEP"}
            [[ $__ks_fn == : ]] && continue
            "$__ks_fn" >/dev/null 2>&1
            compgen -v > "$__ks_d/names.raw"
            kclt_sim_lines "$__ks_d/names.raw"
            for __ks_v in "${KCLT_SIM_L[@]}"; do
                if [[ -n ${__ks_new[$__ks_v]-} ]]; then
                    echo "sim:unlisted-dyn $__ks_fn $__ks_v"; __ks_rc=1
                    unset '__ks_new[$__ks_v]'
                fi
            done
        done
        exit "$__ks_rc"
    )
    __ks_rc=$(( __ks_rc | $? ))
    if (( __ks_rc == 0 )); then echo "sim:ok"; fi
    if (( __ks_cn )); then shopt -s nocasematch; fi
    return "$__ks_rc"
}
