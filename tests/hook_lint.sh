#!/usr/bin/env bash
# hook_lint.sh — the settings hooks lint of kklass/docs/dev/IMAGE_PLAN.md §5.5
# (image stage I1a), sourced by 001_UnitFiles.sh (section 7). Not a test file:
# the ktests runner picks up NNN_*.sh only.
#
# A load image (kk.image) holds a unit's load-time state and re-runs only the
# functions passed to kk.settings (the settings hooks) on each start, so every
# load-time statement whose result can differ between two starts lives in a
# hook (plan §5.1). LOAD-TIME lines: the file-scope code lines and the bodies
# of the file's functions run from them (a function whose name is the first
# word of a command on a load-time line — also after && || ; { ! $( and
# then / do / else / if / while / until — transitively); a hook's body and
# what only a hook runs are not. The rules, on the load-time lines:
#   R1 no public self-default (${X:-d} ${X-d} ${X:=d} ${X=d}), no `${X:+...}`,
#      no `${X+...}` / `${X[*]+...}` preset guard (a readonly reload guard —
#      the same line tests `${X@a} != *r*` — is fine), no `[[ -v X` / `test -v X`, no
#      `${!X}` indirection, no `X+=` append, for a public X (not `_*`, not a
#      local of the function, not bash's / the loader's own: KCLT_HOOK_SYS;
#      for the self-default, not a `${X-}` of a unit's load context in its
#      owner file: KCLT_HOOK_CTX);
#      no locale read ($LC_*, $LANG) or export (export / declare -x of LC_* or
#      LANG, kk.localeDefault); no PATH probe (command -v / -V, type -p / -P /
#      -a, hash); no $$ / $BASHPID; no clock or random value ($RANDOM
#      $SRANDOM $SECONDS $EPOCHSECONDS $EPOCHREALTIME $BASH_MONOSECONDS,
#      printf '%(...)T'); no terminal test ([[ -t N ]], test -t, [ -t); no read
#      of a well-known environment name (KCLT_HOOK_ENV: HOME TERM USER ...;
#      PWD and BASH_SOURCE stay allowed: load context); no read of /proc
#      (`< /proc/...`, `$(< /proc/...)`: a runtime probe, I1b critic M1);
#   R2 no write (X=, X+=, X[K]=, declare -g / export / readonly / unset,
#      printf -v, ${X:=}) of a variable ANOTHER unit lists in its kk.settings
#      (the H1 registry case: the image would hold the write while that
#      unit's hook re-sets the variable);
#   R3 the last command of every function passed to kk.settings is
#      `return 0` or an assignment without a command substitution
#      (`X=v`, `declare -g A=1 B=2`, `declare -ga X`): its rc is kk.settings'
#      rc, and a last `[[ -n ${X-} ]] && Y=1` fails the load where X is unset;
#   R4 KCLT_HOOK_PENDING — units not hooked yet: R1 / R2 / R5 are not applied
#      to them; an entry must name an existing file without a kk.settings line
#      (a hooked file leaves the list). Image stage I1b hooked the last ones
#      and emptied it; 001 asserts that it stays empty (the mechanism stays
#      for the fixtures);
#   R5 no expansion — $X, ${X...}, a bare name inside (( )) / $(( )) — of a
#      variable ANY unit lists in its kk.settings (the hook re-sets it on an
#      image start, a value derived from it at load would stay the writer's:
#      `__W=$(( FX_WIDTH / 2 ))`); LC_* / LANG are R1's;
#   R6 a hook whose body calls kk.localeDefault lists LC_CTYPE (critic L1);
#   R7 a VAR that the hooks of several units list (a registry: tutil owns
#      TUTIL_OUT_*, tfind / tsed / tawk append): each file either kk.uses one
#      of those units at file scope BEFORE its kk.settings line (an
#      appender), or is kk.uses'd by every one of them (the owner) — hooks
#      replay in kk.settings order (__KK_UNIT_SETTINGS), so an appender's
#      hook must come after the owner's; LC_* / LANG (only kk.localeDefault
#      writes them, in any order) are exempt (critic L2).
# The scan, by line: a here-document's body and the inside of a quoted string
# that spans lines are not code; a ` # comment` tail outside quotes is cut; a
# `\` line continues; single-quoted text is not checked by R1 / R5; a
# file-scope function is `NAME() {` / `NAME() (` / `function NAME` at column
# 0 (the brace may open the next line) and ends at the next `}` / `)` at
# column 0, or on its own line for a one-line body. Heuristics, documented by
# the fixtures in 001.

KCLT_HOOK_PENDING=()
KCLT_HOOK_SYS=" BASH BASHOPTS BASHPID BASH_ARGC BASH_ARGV BASH_ARGV0 BASH_COMMAND BASH_LINENO BASH_REMATCH BASH_SOURCE BASH_SUBSHELL BASH_VERSINFO BASH_VERSION FUNCNAME OSTYPE MACHTYPE HOSTTYPE EUID UID PWD KK_UNIT_DIR "
# load context a unit derives from its own file's location: the unit assigns it
# unconditionally at load, before any read, from KK_UNIT_DIR (kklass.sh:
# KKLASS_DIR = the lexically normalised KK_UNIT_DIR), so its value is a function
# of the unit's path — which an image's key holds — and never a caller's. An
# entry is OWNER-FILE:NAME (the owner file matched as a path suffix): only a
# `${NAME-}` read IN THAT FILE (set -u safety for a later run-time call) is no
# self-default; any other form (`${NAME:-d}`, `${NAME:=d}`, ...) and any other
# file are reported (image I1b, critic L3)
KCLT_HOOK_CTX=" kklass/kklass.sh:KKLASS_DIR "
KCLT_HOOK_ENV=" HOME TERM USER LOGNAME SHELL TMPDIR TMP TEMP TZ HOSTNAME DISPLAY PATH EDITOR VISUAL PAGER COLUMNS LINES USERPROFILE LOCALAPPDATA APPDATA LANGUAGE "
KCLT_HOOK_VOLATILE=" RANDOM SRANDOM SECONDS EPOCHSECONDS EPOCHREALTIME BASH_MONOSECONDS "
# the regular expressions (in variables: no shell quoting inside [[ =~ ]])
HK_RE_FN='^(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_.:]*)[[:space:]]*\(\)[[:space:]]*(.*)$'
HK_RE_FN2='^function[[:space:]]+([A-Za-z_][A-Za-z0-9_.:]*)[[:space:]]*(.*)$'
HK_RE_ONE='^\{(.*)\}[[:space:]]*$'
HK_RE_ONEP='^\((.*)\)[[:space:]]*$'
HK_RE_HD='(^|[^<])<<(-?)[[:space:]]*["'"'"']?([A-Za-z_][A-Za-z0-9_]*)'
HK_RE_ASG='(^|[[:space:];&|({!])([A-Za-z_][A-Za-z0-9_]*)(\[[^]]*\])?\+?=(.*)$'
HK_RE_DECL='(^|[[:space:];&|({!])(declare|typeset|local|export|readonly|unset)[[:space:]]+(.*)$'
HK_RE_PRV='printf[[:space:]]+-v[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)(.*)$'
HK_RE_ASD='[$][{]([A-Za-z_][A-Za-z0-9_]*):?=(.*)$'
HK_RE_DEF='[$][{]([A-Za-z][A-Za-z0-9_]*)(\[[^]]*\])?(:?[-=])(.*)$'
HK_RE_ALT='[$][{]([A-Za-z][A-Za-z0-9_]*)(\[[^]]*\])?:[+](.*)$'
HK_RE_GRD='[$][{]([A-Za-z][A-Za-z0-9_]*)(\[[*@]\])?[+](.*)$'
HK_RE_ISV='(\[\[|test|\[)[[:space:]]+(![[:space:]]+)?-v[[:space:]]+["]?([A-Za-z][A-Za-z0-9_]*)(.*)$'
HK_RE_IND='[$][{]!([A-Za-z][A-Za-z0-9_]*)(.*)$'
HK_RE_APP='(^|[^A-Za-z0-9_${])([A-Za-z][A-Za-z0-9_]*)(\[[^]]*\])?[+]=(.*)$'
HK_RE_EXP='[$][{]?[#!]?([A-Za-z_][A-Za-z0-9_]*)(.*)$'
HK_RE_WORD='([A-Za-z_][A-Za-z0-9_]*)(.*)$'
HK_RE_LCR='[$][{]?(LC_[A-Z]+|LANG)([^A-Za-z0-9_]|$)'
HK_RE_LCX='(export|declare[[:space:]]+-[a-zA-Z]*x[a-zA-Z]*)[[:space:]]+([^;&|]*[[:space:]])?(LC_[A-Z]+|LANG)([=[:space:]]|$)'
HK_RE_LCD='(^|[^A-Za-z0-9_.])kk[.]localeDefault([^A-Za-z0-9_.]|$)'
HK_RE_PATH='(^|[[:space:];&|(!])(command[[:space:]]+-[vV]|type[[:space:]]+-[pPa]|hash)([[:space:]]|$)'
HK_RE_PID='(^|[^A-Za-z0-9_])BASHPID([^A-Za-z0-9_]|$)'
HK_RE_TIME='%[(][^)]*[)]T'
HK_RE_TTY='((\[\[|\[|test)[[:space:]]+(![[:space:]]+)?-t[[:space:]])'
HK_RE_PROC='<[[:space:]]*["'"'"']?/proc/'
HK_RE_KKU='(^|[^A-Za-z0-9_.])kk[.]uses[[:space:]]+(.*)$'
HK_RE_LAST1='^((declare|typeset)[[:space:]]+-g[a-zA-Z]*)([[:space:]]+[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(\+?=[^[:space:]]*)?)+$'
HK_RE_LAST2='^([A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?=[^[:space:]]*[[:space:]]*)+$'
HK_RE_CALL='(^|&&|[|][|]|;|[{]|[$][(]|[(]|!|[[:space:]]then|[[:space:]]do|[[:space:]]else|^if|[[:space:]]if|^while|[[:space:]]while|^until|[[:space:]]until)[[:space:]]*([A-Za-z_][A-Za-z0-9_.:]*)(.*)$'
declare -gA HKFB=() HKF1=()
HK_M1=$'\x01' HK_M2=$'\x02'
HK_KEEP=$'[!\'"\\\\\x01\x02]'

# kclt_hk_lines FILE — HKL: FILE's logical lines (code only), HKN: the line
# number of each. A `#` line, a here-document's body and a line inside a
# multi-line quoted string are emptied; a ` # ...` tail outside quotes is
# cut; a `\` line is joined to the next (in code); on the line that closes a
# multi-line string only the text after its last quote of that kind stays.
kclt_hk_lines() {
    local - z="" IFS=$'\n' i l x r c q="" q0 hd="" hdt=0 n j m k p rest pre head
    local -a a
    set -f
    read -r -N 268435456 z < "$1" || :
    z=" ${z//$'\n'/$'\n' }"          # no line is empty: the split keeps them all
    a=($z)
    HKL=() HKN=()
    n=${#a[@]}
    for (( i = 0; i < n; i++ )); do
        l=${a[i]:1}; l=${l%$'\r'}; j=$(( i + 1 ))
        if [[ -n $hd ]]; then
            x=$l
            if (( hdt )); then x=${x#"${x%%[!$'\t']*}"}; fi
            [[ $x == "$hd" ]] && hd=""
            HKL+=(""); HKN+=("$j"); continue
        fi
        q0=$q
        if [[ -n $q ]]; then
            if [[ ( $q != Q && $l != *\'* ) || ( $q == Q && $l != *\"* ) ]]; then HKL+=(""); HKN+=("$j"); continue; fi
        else
            if [[ $l =~ ^[[:space:]]*# || -z ${l//[[:space:]]/} ]]; then HKL+=(""); HKN+=("$j"); continue; fi
            while [[ $l == *'\' ]] && (( i + 1 < n )); do
                i=$(( i + 1 )); l="${l%'\'} ${a[i]:1}"; l=${l%$'\r'}
            done
        fi
        # the quotes of this line: a reduced copy holding only ' " \ and the
        # marks of $' (M2) and a ` #` (M1)
        m=-1
        if [[ -n $q || $l == *[\'\"#]* ]]; then
            x=${l//\\\\/}
            x=${x//\\[!\'\"]/}
            x=${x//\$\'/$HK_M2}
            x=${x//[[:space:]]#/ $HK_M1}
            r=${x//$HK_KEEP/}
            k=0
            for (( p = 0; p < ${#r}; p++ )); do
                c=${r:p:1}
                if [[ $c == "$HK_M1" ]]; then
                    if [[ -z $q ]]; then m=$k; break; fi
                    k=$(( k + 1 )); continue
                fi
                case $q in
                    '') case $c in "'") q=S ;; '"') q=Q ;; "$HK_M2") q=D ;; '\') p=$(( p + 1 )) ;; esac ;;
                    S) if [[ $c == "'" ]]; then q=""; fi ;;
                    D) case $c in '\') p=$(( p + 1 )) ;; "'") q="" ;; esac ;;
                    Q) case $c in '\') p=$(( p + 1 )) ;; '"') q="" ;; esac ;;
                esac
            done
        fi
        if (( m >= 0 )); then
            # cut at the m-th ` #` of the line (counted as in the reduced copy)
            rest=$l pre="" k=0
            while [[ $rest == *[[:space:]]#* ]]; do
                head=${rest%%[[:space:]]#*}
                if (( k == m )); then pre+=$head; break; fi
                pre+=${rest:0:${#head}+2}; rest=${rest:${#head}+2}; k=$(( k + 1 ))
            done
            l=$pre
        fi
        if [[ -n $q0 ]]; then
            if [[ -n $q ]]; then HKL+=(""); HKN+=("$j"); continue; fi
            if [[ $q0 == Q ]]; then l=${l##*\"}; else l=${l##*\'}; fi
        fi
        if [[ -z $q && $l != *'(('* && $l =~ $HK_RE_HD ]]; then
            hd=${BASH_REMATCH[3]} hdt=0
            [[ -n ${BASH_REMATCH[2]} ]] && hdt=1
        fi
        HKL+=("$l") HKN+=("$j")
    done
}

# kclt_hk_sets FILE — HKSET: " FN:VAR,VAR ..." of FILE's kk.settings lines
# (one read and a glob; the file is split only when it has one)
kclt_hk_sets() {
    local - z="" IFS=$'\n' l t
    local -a a w
    set -f
    HKSET=" "
    read -r -N 268435456 z < "$1" || :
    [[ $z == *kk.settings[[:space:]]* ]] || return 0
    z=${z//$'\\\n'/ }
    a=($z)
    for l in "${a[@]}"; do
        [[ $l == kk.settings[[:space:]]* ]] || continue
        l=${l%%[|;&]*}
        IFS=$' \t' w=(${l#kk.settings})
        t="${w[*]:1}"
        HKSET+="${w[0]}:${t// /,} "
    done
}

# kclt_hk_scan FILE — HKTOP: the HKL indexes of the file-scope lines;
# HKFB[NAME]="FROM TO": a file-scope function's body (HKL indexes FROM..TO-1;
# a one-line body: FROM = TO = its line, its text in HKF1[NAME]); HKSET as
# kclt_hk_sets
kclt_hk_scan() {
    local i n l name rest s close
    kclt_hk_lines "$1"
    kclt_hk_sets "$1"
    HKTOP=() HKFB=() HKF1=()
    n=${#HKL[@]}
    for (( i = 0; i < n; i++ )); do
        l=${HKL[i]}
        [[ -n $l ]] || continue
        name=""
        if [[ $l == *'()'* && $l =~ $HK_RE_FN ]]; then name=${BASH_REMATCH[2]} rest=${BASH_REMATCH[3]}
        elif [[ $l == function* && $l =~ $HK_RE_FN2 ]]; then name=${BASH_REMATCH[1]} rest=${BASH_REMATCH[2]}; fi
        if [[ -n $name ]]; then
            rest=${rest%"${rest##*[![:space:]]}"}
            if [[ $rest =~ $HK_RE_ONE || $rest =~ $HK_RE_ONEP ]]; then
                HKFB[$name]="$i $i" HKF1[$name]=${BASH_REMATCH[1]}
                continue
            fi
            s=$i
            if [[ -z $rest ]]; then
                # the opener on the next code line
                i=$(( i + 1 ))
                while (( i < n )) && [[ -z ${HKL[i]//[[:space:]]/} ]]; do i=$(( i + 1 )); done
                rest=${HKL[i]-}; rest=${rest#"${rest%%[![:space:]]*}"}
                s=$i
            fi
            close='}'
            [[ $rest == '('* ]] && close=')'
            i=$(( i + 1 ))
            while (( i < n )) && [[ ${HKL[i]} != "$close"* ]]; do i=$(( i + 1 )); done
            HKFB[$name]="$(( s + 1 )) $i"
            continue
        fi
        HKTOP+=("$i")
    done
}

# kclt_hk_targets TEXT — HKT: the variables TEXT writes (R2); HKLOC: the
# names it declares local (" N ...")
kclt_hk_targets() {
    local t=$1 w v kw g
    HKT=() HKLOC=" "
    while [[ $t =~ $HK_RE_ASG ]]; do HKT+=("${BASH_REMATCH[2]}"); t=${BASH_REMATCH[4]}; done
    t=$1
    while [[ $t =~ $HK_RE_DECL ]]; do
        kw=${BASH_REMATCH[2]} t=${BASH_REMATCH[3]} g=0
        for w in ${t%%[;&|]*}; do
            if [[ $w == -* ]]; then [[ $w == *g* ]] && g=1; continue; fi
            v=${w%%[=[]*}
            [[ $v =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || break
            case $kw in
                local) HKLOC+="$v " ;;
                declare|typeset) if (( g )); then HKT+=("$v"); else HKLOC+="$v "; fi ;;
                *) HKT+=("$v") ;;
            esac
        done
    done
    t=$1
    while [[ $t =~ $HK_RE_PRV ]]; do HKT+=("${BASH_REMATCH[1]}"); t=${BASH_REMATCH[2]}; done
    t=$1
    while [[ $t =~ $HK_RE_ASD ]]; do HKT+=("${BASH_REMATCH[1]}"); t=${BASH_REMATCH[2]}; done
}

# kclt_hk_unsq TEXT — HKU: TEXT without its single-quoted parts ('...' -> '')
kclt_hk_unsq() {
    HKU=$1
    while [[ $HKU =~ ^([^\']*)\'[^\']*\'(.*)$ ]]; do HKU="${BASH_REMATCH[1]}__${BASH_REMATCH[2]}"; done
}

# kclt_hk_r1 TEXT LOCALS — HKR1: the R1 findings of one load-time line
kclt_hk_r1() {
    local t loc=$2 v rest e
    HKR1=""
    kclt_hk_unsq "$1"; t=$HKU
    rest=$t
    while [[ $rest =~ $HK_RE_DEF ]]; do
        v=${BASH_REMATCH[1]} rest=${BASH_REMATCH[4]}
        # a load-context `${X-}` in its owner file (KCLT_HOOK_CTX)
        if [[ ${BASH_REMATCH[3]} == - && -z ${BASH_REMATCH[2]} && $rest == '}'* ]]; then
            for e in $KCLT_HOOK_CTX; do
                [[ ${e##*:} == "$v" && $HK_CURF == *"/${e%:*}" ]] && continue 2
            done
        fi
        [[ $KCLT_HOOK_SYS == *" $v "* || $loc == *" $v "* || $v == LC_* || $v == LANG ]] || HKR1+=" self-default:$v"
    done
    rest=$t
    while [[ $rest =~ $HK_RE_ALT ]]; do
        v=${BASH_REMATCH[1]} rest=${BASH_REMATCH[3]}
        [[ $KCLT_HOOK_SYS == *" $v "* || $loc == *" $v "* ]] || HKR1+=" alt:$v"
    done
    rest=$t
    while [[ $rest =~ $HK_RE_GRD ]]; do
        v=${BASH_REMATCH[1]} rest=${BASH_REMATCH[3]}
        [[ $KCLT_HOOK_SYS == *" $v "* || $loc == *" $v "* || $t == *"\${$v@a} != *r*"* ]] || HKR1+=" guard:$v"
    done
    rest=$t
    while [[ $rest =~ $HK_RE_ISV ]]; do
        v=${BASH_REMATCH[3]} rest=${BASH_REMATCH[4]}
        [[ $KCLT_HOOK_SYS == *" $v "* || $loc == *" $v "* ]] || HKR1+=" is-set:$v"
    done
    rest=$t
    while [[ $rest =~ $HK_RE_IND ]]; do
        v=${BASH_REMATCH[1]} rest=${BASH_REMATCH[2]}
        [[ $KCLT_HOOK_SYS == *" $v "* || $loc == *" $v "* ]] || HKR1+=" indirect:$v"
    done
    rest=$t
    while [[ $rest =~ $HK_RE_APP ]]; do
        v=${BASH_REMATCH[2]} rest=${BASH_REMATCH[4]}
        [[ $loc == *" $v "* ]] || HKR1+=" append:$v"
    done
    rest=$t
    while [[ $rest =~ $HK_RE_EXP ]]; do
        v=${BASH_REMATCH[1]} rest=${BASH_REMATCH[2]}
        if [[ $KCLT_HOOK_VOLATILE == *" $v "* ]]; then HKR1+=" volatile:$v"
        elif [[ $KCLT_HOOK_ENV == *" $v "* && $loc != *" $v "* ]]; then HKR1+=" env:$v"; fi
    done
    if [[ $t =~ $HK_RE_LCR ]]; then HKR1+=" locale-read:${BASH_REMATCH[1]}"; fi
    if [[ $t =~ $HK_RE_LCX ]]; then HKR1+=" locale-export:${BASH_REMATCH[3]}"; fi
    if [[ $t =~ $HK_RE_LCD ]]; then HKR1+=" locale-export:kk.localeDefault"; fi
    if [[ $t =~ $HK_RE_PATH ]]; then v=${BASH_REMATCH[2]}; HKR1+=" path-probe:${v%%[[:space:]]*}"; fi
    if [[ $t == *'$$'* || $t == *'${$}'* || $t =~ $HK_RE_PID ]]; then HKR1+=" pid"; fi
    # (in single quotes: printf's format)
    if [[ $1 =~ $HK_RE_TIME && $1 == *printf* ]]; then HKR1+=" time"; fi
    if [[ $t =~ $HK_RE_TTY ]]; then HKR1+=" tty"; fi
    # a runtime probe from /proc (`< /proc/...`, `$(< /proc/...)`)
    if [[ $1 =~ $HK_RE_PROC ]]; then HKR1+=" proc-read"; fi
}

# kclt_hk_r5 TEXT LOCALS — HKR5: the listed VARs (HKVARS) TEXT expands
kclt_hk_r5() {
    local t loc=$2 v rest seen=" "
    HKR5=""
    kclt_hk_unsq "$1"; t=$HKU
    rest=$t
    while [[ $rest =~ $HK_RE_EXP ]]; do
        v=${BASH_REMATCH[1]} rest=${BASH_REMATCH[2]}
        [[ -n ${HKVARS[$v]-} && $v != LC_* && $v != LANG && $loc != *" $v "* && $seen != *" $v "* ]] || continue
        seen+="$v "; HKR5+=" $v"
    done
    if [[ $t == *'(('* ]]; then
        rest=${t#*'(('}; rest=${rest%'))'*}
        while [[ $rest =~ $HK_RE_WORD ]]; do
            v=${BASH_REMATCH[1]} rest=${BASH_REMATCH[2]}
            [[ -n ${HKVARS[$v]-} && $v != LC_* && $v != LANG && $loc != *" $v "* && $seen != *" $v "* ]] || continue
            seen+="$v "; HKR5+=" $v"
        done
    fi
}

# kclt_hk_uses LINE — HKUN: " NAME ... " of the units the `kk.uses` calls of
# LINE name (options skipped; the words up to || && ; | ) or a redirection)
kclt_hk_uses() {
    local t=$1 w IFS=$' \t\n'
    HKUN=" "
    while [[ $t =~ $HK_RE_KKU ]]; do
        t=${BASH_REMATCH[2]}
        for w in ${t%%[|;&)<>]*}; do
            [[ $w == -* ]] && continue
            [[ $w =~ ^[A-Za-z_][A-Za-z0-9_.]*$ ]] && HKUN+="$w "
        done
    done
}

# kclt_hk_usesall FILE — HKUN: the units FILE's code lines kk.uses anywhere
kclt_hk_usesall() {
    local - z="" IFS=$'\n' l n=" "
    local -a a
    set -f
    read -r -N 268435456 z < "$1" || :
    HKUN=" "
    [[ $z == *kk.uses* ]] || return 0
    a=($z)
    for l in "${a[@]}"; do
        [[ $l == *kk.uses* && ! $l =~ ^[[:space:]]*# ]] || continue
        kclt_hk_uses "$l"; n+=${HKUN# }
    done
    HKUN=$n
}

# kclt_hooklint FILE... — one line per violation, "PATH:LINE: Rn: what"
# (PATH relative to KBOOL_ROOT); nothing when clean. A KCLT_HOOK_PENDING
# entry is relative to KBOOL_ROOT, or absolute.
kclt_hooklint() {
    local f r i j k fn v l t u e cur hooks first last callers seen rest
    local -A uses=() before=() sline=()
    local LC_ALL=C                 # bytes: the regexes run ~20x faster than in a UTF-8 locale
    local -A isp=() run=() floc=()
    local -a lines=()
    declare -gA HKVARS=()
    HKVARS=()
    for r in "${KCLT_HOOK_PENDING[@]}"; do
        if [[ $r == /* || $r == [A-Za-z]:* ]]; then isp[$r]=1; else isp[$KBOOL_ROOT/$r]=1; fi
    done
    # pass 1: every file's kk.settings VARs (R2's "another unit", R5) and the
    # units it kk.uses anywhere (R7)
    for f in "$@"; do
        kclt_hk_sets "$f"
        for t in $HKSET; do
            t=${t#*:}
            for v in ${t//,/ }; do HKVARS[$v]+=" $f "; done
        done
        kclt_hk_usesall "$f"; uses[$f]=$HKUN
    done
    for f in "$@"; do
        r=${f#"$KBOOL_ROOT"/}
        HK_CURF=$f
        kclt_hk_scan "$f"
        if [[ -n ${isp[$f]-} && $HKSET != " " ]]; then
            echo "$r:1: R4: on KCLT_HOOK_PENDING but has kk.settings (hooked: remove it from the list)"
        fi
        # R7: the units kk.uses'd at file scope before each kk.settings line
        before=() sline=() cur=" "
        for i in "${HKTOP[@]}"; do
            l=${HKL[i]}
            if [[ $l =~ ^[[:space:]]*kk\.settings[[:space:]]+([^[:space:]]+) ]]; then
                before[${BASH_REMATCH[1]}]=$cur sline[${BASH_REMATCH[1]}]=${HKN[i]}
            elif [[ $l == *kk.uses* ]]; then
                kclt_hk_uses "$l"; cur+=$HKUN
            fi
        done
        # R3, R6, R7
        hooks=" "
        for t in $HKSET; do
            fn=${t%%:*}
            # R7: a VAR another unit's hook lists too (LC_* / LANG: only
            # kk.localeDefault writes them, in any order): this file loads
            # one of those units before its kk.settings line (it appends to
            # the owner's VAR), or every one of them loads this unit (it is
            # the owner) — else an image start would run the hooks in an
            # order where the owner's runs after an appender's (critic L2)
            v=${t#*:}
            for v in ${v//,/ }; do
                [[ $v == LC_* || $v == LANG ]] && continue
                callers=${HKVARS[$v]// $f /}
                [[ -n ${callers// /} ]] || continue
                k=0
                for l in $callers; do
                    u=${l##*/}; u=${u%.sh}
                    [[ ${before[$fn]-} == *" $u "* ]] && { k=1; break; }
                done
                if (( ! k )); then
                    k=1
                    u=${f##*/}; u=${u%.sh}
                    for l in $callers; do [[ ${uses[$l]} == *" $u "* ]] || k=0; done
                fi
                if (( ! k )); then
                    # name the owner: the lister the other listers load
                    l=${callers# }; l=${l%% *}
                    for e in $callers; do
                        u=${e##*/}; u=${u%.sh} k=1
                        for cur in $callers; do [[ $cur == "$e" || ${uses[$cur]} == *" $u "* ]] || k=0; done
                        (( k )) && { l=$e; break; }
                    done
                    u=${l##*/}; u=${u%.sh}
                    echo "$r:${sline[$fn]-1}: R7: hook $fn lists $v, which ${l#"$KBOOL_ROOT"/}'s hook lists too: kk.uses $u before 'kk.settings $fn' (the owner's hook must run first)"
                fi
            done
            [[ $fn == : ]] && continue
            hooks+="$fn "
            if [[ -z ${HKFB[$fn]-} ]]; then echo "$r:1: R3: hook $fn is not a file-scope function of this file"; continue; fi
            read -r first last <<<"${HKFB[$fn]}"
            # R6: a hook that calls kk.localeDefault lists LC_CTYPE
            if [[ ",${t#*:}," != *,LC_CTYPE,* ]]; then
                if [[ -n ${HKF1[$fn]+x} ]]; then
                    [[ ${HKF1[$fn]} =~ $HK_RE_LCD ]] && echo "$r:${HKN[first]}: R6: hook $fn calls kk.localeDefault but does not list LC_CTYPE"
                else
                    for (( j = first; j < last; j++ )); do
                        if [[ ${HKL[j]} =~ $HK_RE_LCD ]]; then echo "$r:${HKN[j]}: R6: hook $fn calls kk.localeDefault but does not list LC_CTYPE"; break; fi
                    done
                fi
            fi
            l=""
            if [[ -n ${HKF1[$fn]+x} ]]; then
                l=${HKF1[$fn]}; l=${l%"${l##*[![:space:];]}"}; l=${l##*;}
            else
                for (( j = last - 1; j >= first; j-- )); do
                    v=${HKL[j]//[[:space:]]/}
                    if [[ -n $v && $v != '{' && $v != '(' ]]; then l=${HKL[j]}; break; fi
                done
            fi
            l=${l#"${l%%[![:space:]]*}"}; l=${l%"${l##*[![:space:]]}"}; l=${l%;}
            if [[ $l != 'return 0' ]] && { [[ $l == *'$('* || $l == *'`'* ]] || ! [[ $l =~ $HK_RE_LAST1 || $l =~ $HK_RE_LAST2 ]]; }; then
                echo "$r:${HKN[last]}: R3: hook $fn ends with '$l', not 'return 0' or an assignment"
            fi
        done
        [[ -n ${isp[$f]-} ]] && continue
        # the load-time lines: file scope, then the functions run from it
        # (transitively; one-line bodies marked @1)
        lines=() run=() floc=()
        for i in "${HKTOP[@]}"; do lines+=("$i:"); done
        k=0
        while (( k < ${#lines[@]} )); do
            l=${lines[k]}; k=$(( k + 1 ))
            i=${l%%:*}
            t=${HKL[i]}
            if [[ $l == *:@1 ]]; then fn=${l#*:}; t=${HKF1[${fn%:@1}]}; fi
            [[ $t =~ ^[[:space:]]*kk\.settings[[:space:]] ]] && continue
            rest=$t
            while [[ $rest =~ $HK_RE_CALL ]]; do
                fn=${BASH_REMATCH[2]} rest=${BASH_REMATCH[3]}
                [[ -n ${HKFB[$fn]-} && -z ${run[$fn]-} && $hooks != *" $fn "* ]] || continue
                run[$fn]=1
                read -r first last <<<"${HKFB[$fn]}"
                if [[ -n ${HKF1[$fn]+x} ]]; then lines+=("$first:$fn:@1"); continue; fi
                for (( j = first; j < last; j++ )); do lines+=("$j:$fn"); done
            done
        done
        # the locals of each function run at load
        for fn in "${!run[@]}"; do
            read -r first last <<<"${HKFB[$fn]}"
            floc[$fn]=" "
            if [[ -n ${HKF1[$fn]+x} ]]; then kclt_hk_targets "${HKF1[$fn]}"; floc[$fn]+=$HKLOC; continue; fi
            for (( j = first; j < last; j++ )); do kclt_hk_targets "${HKL[j]}"; floc[$fn]+=$HKLOC; done
        done
        for l in "${lines[@]}"; do
            i=${l%%:*} fn=${l#*:}; fn=${fn%:@1}
            t=${HKL[i]}
            [[ $l == *:@1 ]] && t=${HKF1[$fn]}
            [[ -n ${t//[[:space:]]/} ]] || continue
            [[ $t =~ ^[[:space:]]*kk\.settings[[:space:]] ]] && continue
            v=" "; [[ -n $fn ]] && v=${floc[$fn]}
            kclt_hk_r1 "$t" "$v"
            [[ -z $HKR1 ]] || echo "$r:${HKN[i]}: R1:$HKR1${fn:+ (in $fn, run at load)}"
            kclt_hk_r5 "$t" "$v"
            [[ -z $HKR5 ]] || echo "$r:${HKN[i]}: R5: reads${HKR5} (listed by a kk.settings)${fn:+ (in $fn, run at load)}"
            kclt_hk_targets "$t"
            seen=" "
            for v in "${HKT[@]}"; do
                [[ $seen == *" $v "* ]] && continue
                seen+="$v "
                [[ -n ${HKVARS[$v]-} ]] || continue
                [[ -n $fn && ${floc[$fn]} == *" $v "* ]] && continue
                callers=${HKVARS[$v]// $f /}
                [[ -n ${callers// /} ]] || continue
                callers=${callers# }; callers=${callers%% *}
                echo "$r:${HKN[i]}: R2: writes $v, listed by ${callers#"$KBOOL_ROOT"/}'s kk.settings${fn:+ (in $fn, run at load)}"
            done
        done
    done
}
