#!/usr/bin/env bash
[[ ${__KK_UNITS[@]@a} == A* ]] || source "${BASH_SOURCE%thttpserver.sh}../../kbool.sh" || return
kk.unit thttpserver || return $__kk_unit_rc

# thttpserver.sh — the entry point of kcl/thttpserver (PLAN.md §1.2).
#
# Uses the units thttpmessage (THttpRequest, THttpResponse), thttprouter
# (THttpRouteObject, THttpRouter) and kcl/tstopwatch (the access-log timing).
# Own content: the transport seam — THttpTransport (abstract), TReplayTransport
# (the fork-free test double), TNetcatTransport (GNU netcat 0.7.1, two
# alternating listener slots), TSocatTransport (the same mechanism over socat,
# L2.7-N2) — and THttpServer, which picks one of the two (ths._backend).
#
#   THttpRouter.new R; R.RegisterRoute /hello GET hello
#   THttpServer.new S
#   S.Port = 8080; S.Router = R
#   S.Serve                       # blocks; INT/TERM, Terminate or MaxRequests end it
#   S.Active = true               # the same, as FPC's TFPHttpServer.Active := True
#
#   TReplayTransport.new T        # no socket: one raw request file per Accept
#   T.AddRequestFile req1.txt
#   S.Transport = T; S.ServeOne   # RESULT = the code answered
#   T.ResponseFile 0              # RESULT = the path of the captured response
#
# SIGNALS (PLAN §2.6). BeginServe saves `trap -p INT TERM PIPE` (the one fork
# of a Serve), ignores PIPE (a client that left must not kill the shell) and
# traps INT/TERM with a bare assignment to the file-scope flag __THS_SIGNAL —
# nothing else runs inside the trap. The serving loop, ServeOne and
# TNetcatTransport.Accept (at every ≤ 1 s read tick) look at the flag at safe
# points; the loop then runs the private _onSignal (stop + transport
# Shutdown). A signal therefore never cuts a half-sent response, never runs a
# kklass member from inside another object's frame (a private member called
# from a trap there prints a visibility warning — measured P2), and `read -t`
# is not cut short by a trapped signal anyway (measured: it runs to its
# timeout). EndServe restores the saved traps exactly. EXIT is never touched.

# Locale self-heal (kcl README §1.6).
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

# A unit (kklass/USES_PLAN.md §7.4, phase U4): the two header lines at the
# top load kbool.sh when needed and make a repeated `source` a no-op, also
# under `set -eu` (they replaced the D7 re-source guard). Dependencies come
# through kk.uses.
kk.uses kklass_pascal || return
kk.uses thttpmessage thttprouter tstopwatch || return
# ths.* are the PACKAGE's shared helpers (owned by thttpmessage; U44: only a
# file of this folder may share them), not a class: a declared function
# namespace (U40), so no class or instance may take that name.
kk.namespace ths || return

# ---------------------------------------------------------------------------
# File-scope state and helpers (never `static var`: kcl README §1.1).
# ---------------------------------------------------------------------------

# The signal flag: '' or INT / TERM, set by the traps BeginServe installs,
# cleared by BeginServe and EndServe (see SIGNALS above).
declare -g __THS_SIGNAL=""

# ths._bytes STRING — the BYTE length of STRING into the caller's __ths_b.
ths._bytes() {
    local LC_ALL=C
    __ths_b=${#1}
}

# ths._ncFind NAME — NAME (an nc or a socat) resolved into the global
# __THS_NCPATH: a name without `/` is searched on PATH (a walk with `-f`/`-x`,
# no fork, no hash side effect), a path stays as is. NAME unchanged when it is
# not found; the caller checks `/`, `-f` and `-x`. THE one resolver of the
# unit (both BuildArgv and ths._backend share it).
ths._ncFind() {
    local __ths_nc="$1" __ths_p __ths_d
    if [[ "$__ths_nc" != */* ]]; then
        __ths_p="$PATH:"
        while [[ -n "$__ths_p" ]]; do
            __ths_d="${__ths_p%%:*}"
            __ths_p="${__ths_p#*:}"
            if [[ -z "$__ths_d" ]]; then
                __ths_d=.
            fi
            if [[ -f "$__ths_d/$__ths_nc" && -x "$__ths_d/$__ths_nc" ]]; then
                __ths_nc="$__ths_d/$__ths_nc"
                break
            fi
        done
    fi
    __THS_NCPATH="$__ths_nc"
}

# ths._stopPid PID — end the listener PID (a child of the caller) and return;
# it only signals and polls, the caller's own `wait` reaps. Always rc 0.
#   1. `kill -TERM`, polled with ~10 ms naps for at most 300 ms;
#   2. still alive: `kill -KILL`, at most 100 ms more;
#   3. still alive on cygwin / msys: `/usr/bin/kill -f -9 PID` (the cygwin
#      kill utility, -f = through the Windows API). msys 3.6.10 cannot signal a
#      job that is a stub for a FOREIGN-runtime exe (Git-bash running the MSYS2
#      nc.exe): the builtin `kill -TERM`/`-KILL` return 0 and do nothing, and
#      without step 3 the `wait` lasts until nc ends by itself at ListenerTTL
#      (launch L2.8-a). The only fork, on that failure path only.
# The nap (copied from tpipe._nap, not called): `read -t 0.01` on a pty master
# that never has data, opened on the FIRST nap and closed before the return —
# no fd survives the call (a listener must not inherit one); `sleep 0.01`
# (a fork) only where /dev/ptmx cannot be opened. A normal stop costs about
# 1-3 naps, because a listener is still alive right after TERM. The open is
# `{ exec {fd}<>/dev/ptmx; } 2>/dev/null`: a bare `exec … 2>/dev/null` would
# make the redirection permanent (see tpipe._nap).
ths._stopPid() {
    local __ths_sp="$1" __ths_sfd='' __ths_sx='' __ths_sr __ths_sk __ths_sdl __ths_sgone=0
    for __ths_sk in 1 2; do
        if (( __ths_sk == 1 )); then
            kill -TERM "$__ths_sp" 2>/dev/null || :
            __ths_sdl=$(( ${EPOCHREALTIME//[!0-9]/} + 300000 ))
        else
            kill -KILL "$__ths_sp" 2>/dev/null || :
            __ths_sdl=$(( ${EPOCHREALTIME//[!0-9]/} + 100000 ))
        fi
        while :; do
            if ! kill -0 "$__ths_sp" 2>/dev/null; then
                __ths_sgone=1
                break 2
            fi
            if (( ${EPOCHREALTIME//[!0-9]/} >= __ths_sdl )); then
                break
            fi
            if [[ -z "$__ths_sfd" ]]; then
                __ths_sfd=-
                if [[ -c /dev/ptmx ]]; then
                    { exec {__ths_sfd}<>/dev/ptmx; } 2>/dev/null || __ths_sfd=-
                fi
            fi
            __ths_sr=0
            if [[ "$__ths_sfd" != - ]]; then
                read -r -t 0.01 -u "$__ths_sfd" __ths_sx 2>/dev/null || __ths_sr=$?
            fi
            if [[ "$__ths_sfd" == - ]] || (( __ths_sr <= 128 )); then
                sleep 0.01 2>/dev/null || :
            fi
        done
    done
    if [[ -n "$__ths_sfd" && "$__ths_sfd" != - ]]; then
        exec {__ths_sfd}<&-
    fi
    if (( ! __ths_sgone )) && [[ "$OSTYPE" == cygwin || "$OSTYPE" == msys ]] && [[ -x /usr/bin/kill ]]; then
        /usr/bin/kill -f -9 "$__ths_sp" >/dev/null 2>&1 || :
    fi
    return 0
}

# ths._relayExec ERRFILE RELAY CMD… — the end of a StdinRelay listener's
# start: stdin from RELAY (the path of the `<(exec cat fifo.N)` substitution
# the caller hands over), stderr to ERRFILE, then `exec CMD…`. Never returns;
# rc 1 when RELAY cannot be opened. Where `<( )` is a FIFO in TMPDIR (FreeBSD's
# pkg bash, PORTING H14) the shell that made it unlinks it only after its
# writer ended — never, when that shell becomes the listener by `exec`: one
# `sh-np.*` was left per spawn (launch L3.5-7, H44). So a RELAY named like
# bash's FIFOs (`sh-np.XXXXXX`, or `sh-np-N` where bash has no mktemp(3)) is
# unlinked right after the open, which pairs with the writer's (the FIFO is
# no longer needed by name; the fd stays valid). Any other RELAY — /dev/fd/N
# (Linux, cygwin), /proc/self/fd/N — is opened exactly as `< <(…)` would open
# it and nothing else happens; the unlink is the only fork it adds, and only
# on a FIFO bash.
ths._relayExec() {
    local __ths_e="$1" __ths_p="$2"
    shift 2
    exec <"$__ths_p" || exit 1
    if [[ "${__ths_p##*/}" == sh-np[.-]* ]]; then
        command rm -f -- "$__ths_p" 2>/dev/null || :
    fi
    exec "$@" 2>"$__ths_e"
}

# ths._backend [NCBIN] [SOCATBIN] — choose the network backend (L2.7-N1,
# L2.7-N2): sets __THS_BACKEND to gnu | socat | missing | none,
# __THS_BACKEND_BIN to the chosen binary's resolved path (the refused nc /
# socat for none, '' for missing), and __THS_BACKEND_WHY to the reason for
# missing / none ('' otherwise). Precedence (README "Network backend"):
#   a. an explicit netcat — NCBIN (a caller's resolved NcBinary), else $KCL_NC:
#      GNU → gnu; present but not GNU → none (socat is NOT consulted);
#      absent → missing;
#   b. else an explicit socat — SOCATBIN (a caller's SocatBinary), else
#      $KCL_SOCAT: passes the probe → socat, else none;
#   c. else auto: GNU `nc` on PATH → gnu; else `socat` on PATH passing the
#      probe → socat; else a socat on PATH failing the probe → none (BIN = the
#      non-GNU nc if there is one, else the socat); else a present non-GNU nc
#      → none; else missing.
# `gnu` = `NC --version` says GNU Netcat; every other existing nc is named by
# its `--version` / `-h` text (OpenBSD, Ncat, BusyBox, traditional v1.10) and
# NEVER run with the GNU flags (ncat / nc.traditional `-c` and `-e` run
# commands; OpenBSD nc has no accept timeout and keeps its listener open).
# The socat probe: `SOCAT -hhh` lists the accept-timeout option (socat >=
# 1.7.4). The result is cached per "$PATH|$KCL_NC|$KCL_SOCAT|$1|$2": a hit
# forks nothing. EVERY call overwrites the __THS_BACKEND* globals: a caller
# copies them into locals at once.
declare -g __THS_NCPATH=""
: "${__THS_BACKEND:=}" "${__THS_BACKEND_BIN:=}" "${__THS_BACKEND_WHY:=}" "${__THS_BACKEND_KEY:=}"
ths._backend() {
    local __ths_k="$PATH|${KCL_NC-}|${KCL_SOCAT-}|${1-}|${2-}" __ths_bin="${1-}" __ths_sb="${2-}" __ths_fl=""
    if [[ -n "$__THS_BACKEND" && "$__THS_BACKEND_KEY" == "$__ths_k" ]]; then
        return 0
    fi
    __THS_BACKEND_KEY="$__ths_k"
    __THS_BACKEND_WHY=""
    if [[ -z "$__ths_bin" ]]; then
        __ths_bin="${KCL_NC:-}"
    fi
    # a. an explicit netcat
    if [[ -n "$__ths_bin" ]]; then
        ths._ncFind "$__ths_bin"
        __ths_bin="$__THS_NCPATH"
        if [[ "$__ths_bin" != */* || ! -f "$__ths_bin" || ! -x "$__ths_bin" ]]; then
            __THS_BACKEND=missing
            __THS_BACKEND_BIN=""
            __THS_BACKEND_WHY="nc not found (NcBinary, KCL_NC, PATH)"
            return 0
        fi
        __THS_BACKEND_BIN="$__ths_bin"
        if ths._ncFlavour "$__ths_bin"; then
            __THS_BACKEND=gnu
            return 0
        fi
        __THS_BACKEND=none
        __THS_BACKEND_WHY="no usable network backend: $__ths_fl at $__ths_bin is not GNU netcat 0.7.1 (refused: thttpserver never runs another netcat with GNU flags); socat was not consulted because the netcat was set explicitly (NcBinary/KCL_NC)"
        return 0
    fi
    if [[ -z "$__ths_sb" ]]; then
        __ths_sb="${KCL_SOCAT:-}"
    fi
    # b. an explicit socat
    if [[ -n "$__ths_sb" ]]; then
        ths._ncFind "$__ths_sb"
        __ths_sb="$__THS_NCPATH"
        __THS_BACKEND_BIN="$__ths_sb"
        if ths._socatOk "$__ths_sb"; then
            __THS_BACKEND=socat
            return 0
        fi
        __THS_BACKEND=none
        __THS_BACKEND_WHY="no usable network backend: $__ths_sb does not support accept-timeout (socat >= 1.7.4 needed)"
        return 0
    fi
    # c. auto
    ths._ncFind nc
    __ths_bin="$__THS_NCPATH"
    if [[ "$__ths_bin" == */* && -f "$__ths_bin" && -x "$__ths_bin" ]]; then
        if ths._ncFlavour "$__ths_bin"; then
            __THS_BACKEND=gnu
            __THS_BACKEND_BIN="$__ths_bin"
            return 0
        fi
    else
        __ths_bin=""
    fi
    ths._ncFind socat
    __ths_sb="$__THS_NCPATH"
    if ths._socatOk "$__ths_sb"; then
        __THS_BACKEND=socat
        __THS_BACKEND_BIN="$__ths_sb"
        return 0
    fi
    if [[ "$__ths_sb" == */* && -f "$__ths_sb" && -x "$__ths_sb" ]]; then
        # a socat on PATH that fails the probe (older than 1.7.4): none, with
        # or without an nc — never "no socat"
        __THS_BACKEND=none
        if [[ -n "$__ths_bin" ]]; then
            __THS_BACKEND_BIN="$__ths_bin"
            __THS_BACKEND_WHY="no usable network backend: $__ths_fl at $__ths_bin is not GNU netcat 0.7.1 (refused: thttpserver never runs another netcat with GNU flags); $__ths_sb does not support accept-timeout (socat >= 1.7.4 needed)"
        else
            __THS_BACKEND_BIN="$__ths_sb"
            __THS_BACKEND_WHY="nc not found (NcBinary, KCL_NC, PATH); $__ths_sb does not support accept-timeout (socat >= 1.7.4 needed)"
        fi
        return 0
    fi
    if [[ -n "$__ths_bin" ]]; then
        __THS_BACKEND=none
        __THS_BACKEND_BIN="$__ths_bin"
        __THS_BACKEND_WHY="no usable network backend: $__ths_fl at $__ths_bin is not GNU netcat 0.7.1 (refused: thttpserver never runs another netcat with GNU flags); no socat on PATH — install socat (apt/dnf/apk/pkg install socat) or GNU netcat 0.7.1 (Homebrew netcat, FreeBSD net/gnetcat, Arch gnu-netcat, or from source)"
        return 0
    fi
    __THS_BACKEND=missing
    __THS_BACKEND_BIN=""
    __THS_BACKEND_WHY="nc not found (NcBinary, KCL_NC, PATH); no socat on PATH either"
    return 0
}

# ths._ncFlavour NC — rc 0 when the existing executable NC is GNU netcat
# (`NC --version` says GNU Netcat; one fork); else rc 1 and the caller's
# __ths_fl names it from its `--version` / `-h` text (a second fork for an nc
# whose `--version` names nothing). NC is never run with any other argument.
ths._ncFlavour() {
    local __ths_out __ths_t
    __ths_fl=""
    __ths_out="$("$1" --version </dev/null 2>&1 || :)"
    if [[ "$__ths_out" == *"GNU Netcat"* ]]; then
        return 0
    fi
    for __ths_t in 1 2; do
        case "$__ths_out" in
            *OpenBSD*) __ths_fl="OpenBSD netcat" ;;
            *Ncat*) __ths_fl=Ncat ;;
            *BusyBox*) __ths_fl="BusyBox nc" ;;
            *"[v1.10"*) __ths_fl="traditional nc (v1.10)" ;;
            *"[-46"*) __ths_fl="OpenBSD netcat" ;;   # the OpenBSD upstream usage line (no name in it)
        esac
        if [[ -n "$__ths_fl" || "$__ths_t" == 2 ]]; then
            break
        fi
        __ths_out="$("$1" -h </dev/null 2>&1 || :)"
    done
    if [[ -z "$__ths_fl" ]]; then
        __ths_fl="unknown nc"
    fi
    return 1
}

# ths._socatOk SOCAT — rc 0 when SOCAT is an existing executable whose
# `-hhh` lists accept-timeout (socat >= 1.7.4; one fork, no pipe: safe under
# `set -o pipefail`).
ths._socatOk() {
    local __ths_out
    if [[ "$1" != */* || ! -f "$1" || ! -x "$1" ]]; then
        return 1
    fi
    __ths_out="$("$1" -hhh </dev/null 2>&1 || :)"
    [[ "$__ths_out" == *accept-timeout* ]]
}

# ===========================================================================
# THttpTransport — the network seam (PLAN §2.5). The server only knows
# InFd / OutFd / FirstLine / LineConsumed / TimedOut / RemoteAddress /
# LastError, all read-only properties over PROTECTED fields a descendant
# transport sets.
#
#   Accept IDLE_MS REQUEST_TIMEOUT_S → rc 0 a connection · 1 an idle tick ·
#                                      2 fatal (LastError says why)
#   LineConsumed                     → 1 when Accept consumed the request
#                                      line: FirstLine holds it, EVEN WHEN
#                                      EMPTY (a bare LF before the request
#                                      line); 0 when nothing was consumed
#                                      (review 2026-09-30 F5 — FirstLine ''
#                                      alone cannot tell the two apart)
#   CloseConnection                  → close the current connection's fds
#   Shutdown                         → stop listening; release everything
#
# The destructor is empty ON PURPOSE: every descendant may chain with a bare
# `inherited` (a destructor whose parent has none gets rc 127, PLAN C9).
# ===========================================================================
class THttpTransport
    public
        property InFd          read _inFd
        property OutFd         read _outFd
        property FirstLine     read _firstLine
        property LineConsumed  read _lineConsumed
        property TimedOut      read _timedOut
        property RemoteAddress read _remoteAddress
        property LastError     read _lastError
        constructor Create
        destructor  Destroy
        abstract func Accept
        abstract proc CloseConnection
        abstract proc Shutdown
    protected
        var _inFd
        var _outFd
        var _firstLine
        var _lineConsumed
        var _timedOut
        var _remoteAddress
        var _lastError
end

THttpTransport.Create() {
    _inFd=""
    _outFd=""
    _firstLine=""
    _lineConsumed=0
    _timedOut=0
    _remoteAddress=""
    _lastError=""
}

THttpTransport.Destroy() {
    :
}

build THttpTransport

# ===========================================================================
# TReplayTransport — the test double: no socket, no fork (PLAN §2.5).
#
# Each Accept opens the NEXT added request file on InFd (`exec {fd}<FILE`) and
# a fresh capture file on OutFd (`exec {fd}>CAPTURE`); with none left it is
# rc 2 (LastError set). The capture of the N-th accepted request (0-based) is
# `<request file>.N.out`, reported by `ResponseFile N`. An Accept while a
# connection is still open closes that one first. FirstLine is always '' and
# LineConsumed 0 (the parser reads the request line itself), TimedOut 0,
# RemoteAddress ''.
#
# Per-instance arrays: `${inst}_rqf` (request files, in order) and
# `${inst}_rsf` (capture files, by accept ordinal), freed in Destroy.
# ===========================================================================
class TReplayTransport : THttpTransport
    public
        constructor Create
        destructor  Destroy
        proc AddRequestFile
        func ResponseFile
        override func Accept
        override proc CloseConnection
        override proc Shutdown
    private
        var _next
end

TReplayTransport.Create() {
    inherited
    _next=0
    declare -ga "${__inst__}_rqf=()" "${__inst__}_rsf=()"
}

TReplayTransport.Destroy() {
    kk.call_silent "$__inst__" Shutdown
    unset -v "${__inst__}_rqf" "${__inst__}_rsf"
    inherited
}

# AddRequestFile FILE — one raw request per Accept, in order. rc 2 for '',
# rc 1 for a file that is not a readable regular file.
TReplayTransport.AddRequestFile() {
    local __ths_f="${1:-}"
    if [[ -z "$__ths_f" ]]; then
        kk.debug "Error: TReplayTransport.AddRequestFile: empty file name"
        return 2
    fi
    if [[ ! -f "$__ths_f" || ! -r "$__ths_f" ]]; then
        kk.debug "Error: TReplayTransport.AddRequestFile: '$__ths_f' is not a readable file"
        return 1
    fi
    local -n __ths_q="${__inst__}_rqf"
    __ths_q+=("$__ths_f")
    return 0
}

# ResponseFile INDEX — the capture path of the INDEX-th accepted request
# (0-based); rc 1 for an index that was not accepted (or is not an integer).
TReplayTransport.ResponseFile() {
    local __ths_i="${1:-}"
    local -n __ths_s="${__inst__}_rsf"
    if ! kk.isInt "$__ths_i" __ths_i || (( __ths_i < 0 || __ths_i >= ${#__ths_s[@]} )); then
        kk.debug "Error: TReplayTransport.ResponseFile: no captured response #$__ths_i"
        kk._return ""
        return 1
    fi
    kk._return "${__ths_s[__ths_i]}"
    return 0
}

# Accept IDLE_MS REQUEST_TIMEOUT_S — both ignored (a file never idles and never
# stalls). RESULT = the accept ordinal on rc 0.
TReplayTransport.Accept() {
    local __ths_n="$_next" __ths_f __ths_cap __ths_in="" __ths_out=""
    local -n __ths_q="${__inst__}_rqf" __ths_s="${__inst__}_rsf"
    if [[ -n "$_inFd" || -n "$_outFd" ]]; then
        kk.call_silent "$__inst__" CloseConnection
    fi
    if (( __ths_n >= ${#__ths_q[@]} )); then
        _lastError="TReplayTransport: no request file left"
        kk.debug "Error: $_lastError"
        kk._return ""
        return 2
    fi
    __ths_f="${__ths_q[__ths_n]}"
    __ths_cap="$__ths_f.$__ths_n.out"
    if ! { exec {__ths_in}<"$__ths_f"; } 2>/dev/null; then
        _lastError="TReplayTransport: cannot open '$__ths_f'"
        kk.debug "Error: $_lastError"
        kk._return ""
        return 2
    fi
    if ! { exec {__ths_out}>"$__ths_cap"; } 2>/dev/null; then
        exec {__ths_in}<&-
        _lastError="TReplayTransport: cannot create '$__ths_cap'"
        kk.debug "Error: $_lastError"
        kk._return ""
        return 2
    fi
    _inFd="$__ths_in"
    _outFd="$__ths_out"
    _firstLine=""
    _lineConsumed=0
    _timedOut=0
    _remoteAddress=""
    __ths_s[__ths_n]="$__ths_cap"
    _next=$(( __ths_n + 1 ))
    kk._return "$__ths_n"
    return 0
}

# CloseConnection — closes InFd and OutFd (if open); rc 0.
TReplayTransport.CloseConnection() {
    local __ths_fd
    if [[ -n "$_inFd" ]]; then
        __ths_fd="$_inFd"
        exec {__ths_fd}<&-
    fi
    if [[ -n "$_outFd" ]]; then
        __ths_fd="$_outFd"
        exec {__ths_fd}>&-
    fi
    _inFd=""
    _outFd=""
    return 0
}

# Shutdown — nothing listens; closes the current connection, if any.
TReplayTransport.Shutdown() {
    kk.call_silent "$__inst__" CloseConnection
    return 0
}

build TReplayTransport

# ===========================================================================
# TNetcatTransport — GNU netcat 0.7.1 as the network backend (PLAN §2.5, D5).
#
# One nc per connection: GNU 0.7.1 has no -k, so a listener is started IN
# ADVANCE and blocks in accept; bash waits in `read -t` on its stdout, and the
# first bytes of a request arriving there ARE the event. Two alternating
# slots: right after the current connection's request line arrives, the OTHER
# slot's listener is spawned (D5), so a second client can connect while the
# first request is handled (queue depth 1).
#
# A slot = a FIFO feeding nc's stdin, a process-substitution fd reading its
# stdout, a `-vv` stderr file and a pid, under a `mktemp -d` dir (created at
# the first Accept, removed by Shutdown). Every listener gets a FRESH FIFO
# (`fifo.N`, N = a generation number of the transport, never reused — launch
# L3.5-10, _newFifo). The mechanism is the P2 spike's,
# measured on bash 5.2.37 and 5.3.9 (PLAN §1.1, ledger measured_p2):
#   * the FIFO writer is opened O_WRONLY (`exec {wr}>fifo`) — an O_RDWR writer
#     never lets nc see EOF (C1);
#   * the listener child closes the OTHER slot's fds before exec — otherwise
#     it inherits the live connection's writer and holds it open (C4);
#   * nc's stdin comes through `cat` (StdinRelay 1): a Git-runtime FIFO as
#     msys64 nc's stdin dies on accept under bash 5.2 (C3); cat's own stderr
#     is silenced (PIPE is ignored while serving, so a cat whose nc died would
#     print `write error`);
#   * CloseConnection DRAINS: close wr → read rd to EOF (nc flushed, closed
#     and exited; unread request bytes are swallowed, no RST) within
#     CloseTimeout → close rd → kill ONLY past that deadline → wait (C2);
#     the slot's FIFO is then dropped (queued for unlinking) and never opened
#     again: the `cat` relay is the listener's child, nothing can wait for
#     it, and one that has not yet run since the writer closed has not seen
#     its EOF — on a REUSED FIFO the next writer's open cleared that EOF and
#     the old cat read on beside the new one, taking the first write(2) of
#     the next response (launch L3.5-10). On its own inode it sees EOF and
#     exits by itself.
# nc's exit status is always 1: the state comes from its -vv stderr —
# `Listening on` (bound), `Connection from A:P` (accepted), `Listen mode
# failed: Connection timed out` (-w expired: respawn), anything else (bind
# failure, exec failure, …) is fatal: Accept rc 2 with LastError = that line,
# never a silent respawn loop (C6). `-w ListenerTTL` limits accept only: it is
# an orphan time-to-live, not a request timeout (C5).
#
# Per-request forks: the listener spawn (fork + cat relay + nc, ≈35–45 ms,
# synchronous). The FIFOs come in batches of __THS_FIFO_BATCH: one mkfifo,
# and one rm of the dropped ones, per batch (each costs ≈25–40 ms on msys:
# ≈3–4 ms per request there). mktemp once per dir, rm -rf once per Shutdown.
# FD HYGIENE: a background process a handler starts inherits the current
# connection's writer AND the other slot's (pre-spawned) writer: it holds the
# connection open until CloseTimeout, and while it lives the `cat` relays of
# those FIFOs never see EOF — they outlive the close (and Shutdown) as long as
# that process does.
# ===========================================================================
class TNetcatTransport : THttpTransport
    public
        var NcBinary
        var Address
        var Port
        var ListenerTTL
        var CloseTimeout
        var StdinRelay
        constructor Create
        destructor  Destroy
        func BuildArgv
        override func Accept
        override proc CloseConnection
        override proc Shutdown
    private
        var _dir
        var _cur
        var _pid0
        var _pid1
        var _rd0
        var _rd1
        var _wr0
        var _wr1
        var _seen0
        var _seen1
        var _fifo0
        var _fifo1
        var _gen
        var _made
        var _dead
        proc _newFifo
        proc _spawn
        proc _closeSlot
        func _state
end

# FIFOs created by one mkfifo (TNetcatTransport._newFifo)
declare -g __THS_FIFO_BATCH=16

TNetcatTransport.Create() {
    inherited
    NcBinary=""
    Address=127.0.0.1
    Port=8080
    ListenerTTL=60
    CloseTimeout=2
    StdinRelay=1
    _dir=""
    _cur=0
    _pid0=""
    _pid1=""
    _rd0=""
    _rd1=""
    _wr0=""
    _wr1=""
    _seen0=""
    _seen1=""
    _fifo0=""
    _fifo1=""
    _gen=0
    _made=0
    _dead=""
}

TNetcatTransport.Destroy() {
    kk.call_silent "$__inst__" Shutdown
    inherited
}

# BuildArgv OUTARR — the listener's argv: NC -l -c -vv -n -w TTL -s ADDR -p
# PORT; RESULT = the element count. NC = NcBinary, else $KCL_NC, else `nc`
# found on PATH (a walk over PATH with `-f`/`-x`, no fork, no hash side
# effect); a name without `/` is searched on PATH, a path must be an
# executable file. rc 1 + LastError 'nc not found …' when there is none; rc 2
# for an unusable OUTARR or Port outside 1–65535, ListenerTTL < 1, Address ''.
# Virtual: a descendant for another nc flavour overrides it.
TNetcatTransport.BuildArgv() {
    local __ths_o="${1:-}" __ths_nc="$NcBinary" __ths_port="$Port" __ths_ttl="$ListenerTTL"
    if ! kk._outName "$__ths_o" __ths_ __THS_; then
        kk.debug "Error: TNetcatTransport.BuildArgv: unusable output array name '$__ths_o'"
        kk._return ""
        return 2
    fi
    if ! kk.isInt "$__ths_port" __ths_port || (( __ths_port < 1 || __ths_port > 65535 )) \
       || ! kk.isInt "$__ths_ttl" __ths_ttl || (( __ths_ttl < 1 )) || [[ -z "$Address" ]]; then
        _lastError="TNetcatTransport: Port must be 1-65535, ListenerTTL >= 1 and Address non-empty"
        kk.debug "Error: $_lastError"
        kk._return ""
        return 2
    fi
    if [[ -z "$__ths_nc" ]]; then
        __ths_nc="${KCL_NC:-}"
    fi
    if [[ -z "$__ths_nc" ]]; then
        __ths_nc=nc
    fi
    ths._ncFind "$__ths_nc"
    __ths_nc="$__THS_NCPATH"
    if [[ "$__ths_nc" != */* || ! -f "$__ths_nc" || ! -x "$__ths_nc" ]]; then
        _lastError="nc not found (NcBinary '$NcBinary', KCL_NC '${KCL_NC:-}', PATH)"
        kk.debug "Error: TNetcatTransport.BuildArgv: $_lastError"
        kk._return ""
        return 1
    fi
    ths._backend "$__ths_nc"
    local __ths_bk="$__THS_BACKEND" __ths_why="$__THS_BACKEND_WHY"
    if [[ "$__ths_bk" != gnu ]]; then
        # nc came from PATH, not from NcBinary / KCL_NC: the "set explicitly"
        # tail of the reason would mislead
        if [[ "$__ths_bk" == none && -z "$NcBinary" && -z "${KCL_NC:-}" ]]; then
            __ths_why="${__ths_why%"; socat was not consulted because the netcat was set explicitly (NcBinary/KCL_NC)"}; TNetcatTransport runs GNU netcat only (use TSocatTransport, or leave THttpServer.Transport '' for automatic selection)"
        fi
        _lastError="$__ths_why"
        kk.debug "Error: TNetcatTransport.BuildArgv: $_lastError"
        kk._return ""
        return 2
    fi
    local -n __ths_out="$__ths_o"
    __ths_out=("$__ths_nc" -l -c -vv -n -w "$__ths_ttl" -s "$Address" -p "$__ths_port")
    kk._return "${#__ths_out[@]}"
    return 0
}

# _newFifo SLOT — a FRESH FIFO for SLOT's next listener into _fifoSLOT (launch
# L3.5-10): `$_dir/fifo.N`, N = _gen, counted up and never reused, so the
# relay of an earlier listener never shares a FIFO with a later one. The names
# come from a pool: when it is used up, ONE `rm -f` unlinks the FIFOs that
# _closeSlot dropped since the last batch (_dead: their numbers), then ONE
# mkfifo creates the next __THS_FIFO_BATCH. A dropped FIFO may still be open
# (by a relay that has not run yet); unlinking an open FIFO leaves its open
# ends valid (measured on msys as well). A batch size that is not a positive
# integer counts as 16; a name an earlier failed _spawn left in _fifoSLOT is
# dropped too. rc 1 + LastError (mkfifo's message) when mkfifo fails; the
# partial batch is removed.
TNetcatTransport._newFifo() {
    local __ths_s="$1" __ths_g __ths_e __ths_n="$__THS_FIFO_BATCH" IFS=' '
    local -a __ths_l=()
    local -n __ths_fS="_fifo$__ths_s"
    [[ "$__ths_n" =~ ^[1-9][0-9]*$ ]] || __ths_n=16
    # a name an earlier _spawn took but never opened (it failed after us)
    if [[ "$__ths_fS" == "$_dir/fifo."* ]]; then
        _dead+="${_dead:+ }${__ths_fS##*/fifo.}"
    fi
    __ths_fS=""
    if (( _gen >= _made )); then
        if [[ -n "$_dead" ]]; then
            for __ths_g in $_dead; do
                __ths_l+=("$_dir/fifo.$__ths_g")
            done
            command rm -f -- "${__ths_l[@]}" 2>/dev/null || :
            _dead=""
            __ths_l=()
        fi
        for (( __ths_g = _made; __ths_g < _made + __ths_n; __ths_g++ )); do
            __ths_l+=("$_dir/fifo.$__ths_g")
        done
        if ! { command mkfifo -- "${__ths_l[@]}" 2>"$_dir/mkfifo.err"; } 2>/dev/null; then
            # mkfifo makes what it can: the partial batch goes, so a retry
            # after a transient failure (a full TMPDIR) can succeed
            __ths_e=""
            { IFS= read -r __ths_e < "$_dir/mkfifo.err"; } 2>/dev/null || :
            command rm -f -- "${__ths_l[@]}" 2>/dev/null || :
            _lastError="TNetcatTransport: cannot create the FIFOs under '$_dir'${__ths_e:+: $__ths_e}"
            kk.debug "Error: $_lastError"
            return 1
        fi
        _made=$(( _made + __ths_n ))
    fi
    __ths_fS="$_dir/fifo.$_gen"
    _gen=$(( _gen + 1 ))
    return 0
}

# _spawn SLOT — start SLOT's listener (PLAN §2.5) on a FRESH FIFO (_newFifo):
# the err file truncated, nc started through a process substitution whose
# child closes the OTHER slot's fds first, its stdin fed from the slot's FIFO
# through `cat`, its -vv stderr to the slot's err file; then the O_WRONLY
# writer (the open pairs with the relay's and returns once it ran — the FIFO
# is new, so its only reader is this relay). rc 1 (LastError set) if no FIFO,
# no argv or no child could be started.
TNetcatTransport._spawn() {
    local __ths_s="$1" __ths_dir="$_dir" __ths_rd="" __ths_wr="" __ths_wo __ths_ro __ths_pid __ths_ff
    local -a ths_argv=()
    if ! "$__inst__.BuildArgv" ths_argv; then
        return 1
    fi
    local -n __ths_rdS="_rd$__ths_s" __ths_wrS="_wr$__ths_s" __ths_pidS="_pid$__ths_s" __ths_seenS="_seen$__ths_s" __ths_fS="_fifo$__ths_s"
    if ! "$__inst__._newFifo" "$__ths_s"; then
        return 1
    fi
    __ths_ff="$__ths_fS"
    local -n __ths_rdO="_rd$(( 1 - __ths_s ))" __ths_wrO="_wr$(( 1 - __ths_s ))"
    __ths_wo="$__ths_wrO"
    __ths_ro="$__ths_rdO"
    if ! { : > "$__ths_dir/err$__ths_s"; } 2>/dev/null; then
        _lastError="TNetcatTransport: cannot write '$__ths_dir/err$__ths_s'"
        kk.debug "Error: $_lastError"
        return 1
    fi
    if [[ "$StdinRelay" == 0 ]]; then
        if ! exec {__ths_rd}< <(
                if [[ -n "$__ths_wo" ]]; then exec {__ths_wo}>&-; fi
                if [[ -n "$__ths_ro" ]]; then exec {__ths_ro}<&-; fi
                export LC_ALL=C
                exec "${ths_argv[@]}" <"$__ths_ff" 2>"$__ths_dir/err$__ths_s"
            ); then
            _lastError="TNetcatTransport: cannot start the listener"
            kk.debug "Error: $_lastError"
            return 1
        fi
    else
        if ! exec {__ths_rd}< <(
                if [[ -n "$__ths_wo" ]]; then exec {__ths_wo}>&-; fi
                if [[ -n "$__ths_ro" ]]; then exec {__ths_ro}<&-; fi
                export LC_ALL=C
                ths._relayExec "$__ths_dir/err$__ths_s" <(exec cat "$__ths_ff" 2>/dev/null) "${ths_argv[@]}"
            ); then
            _lastError="TNetcatTransport: cannot start the listener"
            kk.debug "Error: $_lastError"
            return 1
        fi
    fi
    __ths_pid=$!
    exec {__ths_wr}>"$__ths_ff"
    __ths_rdS="$__ths_rd"
    __ths_wrS="$__ths_wr"
    __ths_pidS="$__ths_pid"
    __ths_seenS=""
    return 0
}

# _closeSlot SLOT MODE [DEADLINE_US] — release SLOT (PLAN §2.5 C2). MODE drain:
# close wr, drain rd to EOF within CloseTimeout (or until the absolute
# DEADLINE_US a caller shares between slots), close rd, kill ONLY past the
# deadline, wait. MODE eof: rd is already at EOF (nc exited) — close both, wait.
# Then, both modes: the slot's FIFO is DROPPED — its number queued in _dead
# for the next batch's unlink (_newFifo) — and never opened again (launch
# L3.5-10). The `cat` relay reading it is the listener's child (init reaps
# it; the server cannot wait for it), and one that has not yet run since the
# writer closed has not seen its EOF. On a reused FIFO the next _spawn's
# writer open cleared that EOF and the old cat read on as a SECOND reader: it
# took the first write(2) of the next response on that slot — bash's printf
# writes line by line where stdio is BSD's (FreeBSD: the status line alone)
# — and lost it into its dead listener. On a FIFO nobody reopens it sees EOF
# whenever it runs, and exits.
TNetcatTransport._closeSlot() {
    local __ths_s="$1" __ths_mode="${2:-drain}" __ths_rd __ths_wr __ths_pid __ths_eof=0
    local __ths_x __ths_r __ths_left __ths_dl __ths_ct="$CloseTimeout"
    local -n __ths_rdS="_rd$__ths_s" __ths_wrS="_wr$__ths_s" __ths_pidS="_pid$__ths_s" __ths_seenS="_seen$__ths_s" __ths_fS="_fifo$__ths_s"
    if ! kk.isInt "$__ths_ct" __ths_ct || (( __ths_ct < 0 )); then
        __ths_ct=2
    fi
    __ths_rd="$__ths_rdS"
    __ths_wr="$__ths_wrS"
    __ths_pid="$__ths_pidS"
    if [[ "$__ths_mode" == eof ]]; then
        __ths_eof=1
    fi
    if [[ -n "$__ths_wr" ]]; then
        exec {__ths_wr}>&-
    fi
    if [[ -n "$__ths_rd" ]]; then
        if (( ! __ths_eof )); then
            __ths_dl="${3:-}"
            if ! kk.isInt "$__ths_dl" __ths_dl; then
                __ths_dl=$(( ${EPOCHREALTIME//[!0-9]/} + __ths_ct * 1000000 ))
            fi
            local LC_ALL=C
            while ths._left "$__ths_dl"; do
                __ths_r=0
                IFS= read -r -d '' -n 8192 -t "$__ths_left" -u "$__ths_rd" __ths_x 2>/dev/null || __ths_r=$?
                if (( __ths_r == 1 )); then
                    __ths_eof=1
                    break
                fi
                if (( __ths_r > 128 )); then
                    break
                fi
            done
        fi
        exec {__ths_rd}<&-
    fi
    if [[ -n "$__ths_pid" ]]; then
        if (( ! __ths_eof )); then
            ths._stopPid "$__ths_pid"
        fi
        wait "$__ths_pid" 2>/dev/null || :
    fi
    if [[ -n "$__ths_fS" ]]; then
        _dead+="${_dead:+ }${__ths_fS##*/fifo.}"
        __ths_fS=""
    fi
    __ths_rdS=""
    __ths_wrS=""
    __ths_pidS=""
    __ths_seenS=""
    return 0
}

# _state SLOT — the listener's state from its -vv stderr file (fork-free):
# RESULT = listening | connected | ttl | failed:<first unknown line> | none
# (no file / empty: not started yet); REPLY = the remote 'IP:PORT' when
# connected.
TNetcatTransport._state() {
    local __ths_f="$_dir/err$1" __ths_l __ths_st=none __ths_first="" __ths_conn="" __ths_ttl=0
    REPLY=""
    if [[ ! -f "$__ths_f" ]]; then
        kk._return none
        return 0
    fi
    while IFS= read -r __ths_l || [[ -n "$__ths_l" ]]; do
        __ths_l="${__ths_l%"$__THS_CR"}"
        if [[ "$__ths_l" == 'Listening on '* ]]; then
            __ths_st=listening
        elif [[ "$__ths_l" == 'Connection from '* ]]; then
            __ths_conn="${__ths_l#Connection from }"
        elif [[ "$__ths_l" == 'Listen mode failed: Connection timed out' ]]; then
            __ths_ttl=1
        elif [[ -n "$__ths_l" && "$__ths_l" != 'Total received bytes:'* && "$__ths_l" != 'Total sent bytes:'* && -z "$__ths_first" ]]; then
            __ths_first="$__ths_l"
        fi
    done < "$__ths_f"
    if [[ -n "$__ths_conn" ]]; then
        REPLY="$__ths_conn"
        kk._return connected
    elif (( __ths_ttl )); then
        kk._return ttl
    elif [[ -n "$__ths_first" ]]; then
        kk._return "failed:$__ths_first"
    else
        kk._return "$__ths_st"
    fi
    return 0
}

# Accept IDLE_MS REQUEST_TIMEOUT_S (PLAN §2.5, C5, C6) → rc 0 a connection
# (InFd/OutFd/RemoteAddress; FirstLine = the consumed request line with
# LineConsumed 1 — an EMPTY line included, review F5; or TimedOut 1 and
# LineConsumed 0 for a client silent past REQUEST_TIMEOUT_S — the server
# answers 408) · rc 1 an idle tick (the
# listener stays alive), a client that connected and left, or a signal
# (__THS_SIGNAL) · rc 2 fatal, LastError says why. A connection still open is
# closed first. The request line is read in ≤ 1 s ticks, partial input
# accumulated; right after it arrives the OTHER slot is spawned (D5). A
# pre-spawned listener that died is spawned once more; a listener spawned in
# this call that fails is fatal at once.
TNetcatTransport.Accept() {
    local __ths_idle="${1:-}" __ths_rt="${2:-}"
    if ! kk.isInt "$__ths_idle" __ths_idle || (( __ths_idle < 0 )) \
       || ! kk.isInt "$__ths_rt" __ths_rt || (( __ths_rt < 0 )); then
        kk.debug "Error: TNetcatTransport.Accept: usage: IDLE_MS REQUEST_TIMEOUT_S (integers >= 0)"
        kk._return ""
        return 2
    fi
    local __ths_s __ths_spawned=0 __ths_t0 __ths_now __ths_us __ths_tick __ths_acc="" __ths_chunk
    local __ths_r __ths_st __ths_rd __ths_seen
    local -a ths_probe=()
    if [[ -n "$_inFd" || -n "$_outFd" ]]; then
        kk.call_silent "$__inst__" CloseConnection
    fi
    _firstLine=""
    _lineConsumed=0
    _timedOut=0
    _remoteAddress=""
    if [[ -n "$__THS_SIGNAL" ]]; then
        kk._return ""
        return 1
    fi
    if [[ -z "$_dir" ]]; then
        if ! "$__inst__.BuildArgv" ths_probe; then
            kk._return ""
            return 2
        fi
        _dir="$(mktemp -d "${TMPDIR:-/tmp}/thttpserver.XXXXXX" 2>/dev/null)" || _dir=""
        _gen=0
        _made=0
        _dead=""
        if [[ -z "$_dir" ]]; then
            _lastError="TNetcatTransport: cannot create the temp dir under '${TMPDIR:-/tmp}'"
            kk.debug "Error: $_lastError"
            kk._return ""
            return 2
        fi
    fi
    local LC_ALL=C
    __ths_s="$_cur"
    local -n __ths_rdS="_rd$__ths_s" __ths_wrS="_wr$__ths_s" __ths_pidS="_pid$__ths_s" __ths_seenS="_seen$__ths_s"
    if [[ -z "$__ths_pidS" ]]; then
        if ! "$__inst__._spawn" "$__ths_s"; then
            kk._return ""
            return 2
        fi
        __ths_spawned=1
    fi
    __ths_t0=${EPOCHREALTIME//[!0-9]/}
    while :; do
        if [[ -n "$__THS_SIGNAL" || -z "$_dir" ]]; then
            kk._return ""
            return 1
        fi
        __ths_rd="$__ths_rdS"
        __ths_tick=1
        if (( __ths_idle > 0 )); then
            __ths_us=$(( __ths_idle * 1000 - (${EPOCHREALTIME//[!0-9]/} - __ths_t0) ))
            if (( __ths_us < 1000000 )); then
                if (( __ths_us < 10000 )); then
                    __ths_us=10000
                fi
                printf -v __ths_tick '0.%06d' "$__ths_us"
            fi
        fi
        __ths_chunk=""
        __ths_r=0
        IFS= read -r -n $(( 8194 - ${#__ths_acc} )) -t "$__ths_tick" -u "$__ths_rd" __ths_chunk 2>/dev/null || __ths_r=$?
        __ths_acc+="$__ths_chunk"
        "$__inst__._state" "$__ths_s"
        __ths_st="$RESULT"
        if (( __ths_r == 0 )); then
            _firstLine="$__ths_acc"
            _lineConsumed=1
            _remoteAddress="$REPLY"
            _inFd="$__ths_rdS"
            _outFd="$__ths_wrS"
            "$__inst__._spawn" $(( 1 - __ths_s )) || :
            kk._return ""
            return 0
        fi
        if (( __ths_r > 128 )); then
            __ths_now=${EPOCHREALTIME//[!0-9]/}
            if [[ "$__ths_st" == connected || -n "$__ths_acc" ]]; then
                __ths_seen="$__ths_seenS"
                if [[ -z "$__ths_seen" ]]; then
                    __ths_seen="$__ths_now"
                    __ths_seenS="$__ths_now"
                fi
                if (( __ths_now - __ths_seen >= __ths_rt * 1000000 )); then
                    _timedOut=1
                    _remoteAddress="$REPLY"
                    _inFd="$__ths_rdS"
                    _outFd="$__ths_wrS"
                    "$__inst__._spawn" $(( 1 - __ths_s )) || :
                    kk._return ""
                    return 0
                fi
            elif [[ "$__ths_st" == listening || "$__ths_st" == none ]]; then
                if (( __ths_idle > 0 && __ths_now - __ths_t0 >= __ths_idle * 1000 )); then
                    kk._return ""
                    return 1
                fi
            fi
            continue
        fi
        # EOF: this slot's nc has exited.
        if [[ "$__ths_st" == connected ]]; then
            "$__inst__._closeSlot" "$__ths_s" eof
            kk._return ""
            return 1
        fi
        if [[ "$__ths_st" == ttl ]]; then
            "$__inst__._closeSlot" "$__ths_s" eof
            if ! "$__inst__._spawn" "$__ths_s"; then
                kk._return ""
                return 2
            fi
            __ths_acc=""
            continue
        fi
        if (( ! __ths_spawned )); then
            "$__inst__._closeSlot" "$__ths_s" eof
            if ! "$__inst__._spawn" "$__ths_s"; then
                kk._return ""
                return 2
            fi
            __ths_spawned=1
            __ths_acc=""
            continue
        fi
        if [[ "$__ths_st" == failed:* ]]; then
            _lastError="${__ths_st#failed:}"
        else
            _lastError="TNetcatTransport: the listener exited ($__ths_st)"
        fi
        "$__inst__._closeSlot" "$__ths_s" eof
        kk.debug "Error: TNetcatTransport.Accept: $_lastError"
        kk._return ""
        return 2
    done
}

# CloseConnection — the drained close of the current connection (PLAN §2.5
# C2), then the other slot becomes current. rc 0; nothing open → rc 0.
TNetcatTransport.CloseConnection() {
    local __ths_s="$_cur"
    local -n __ths_pidS="_pid$__ths_s"
    _inFd=""
    _outFd=""
    _firstLine=""
    _lineConsumed=0
    _timedOut=0
    _remoteAddress=""
    if [[ -z "$__ths_pidS" ]]; then
        return 0
    fi
    "$__inst__._closeSlot" "$__ths_s" drain
    _cur=$(( 1 - __ths_s ))
    return 0
}

# Shutdown — stop listening, release both slots, remove the FIFOs, the stderr
# files and the dir. Idempotent.
#   * a slot whose listener has ACCEPTED a client (`Connection from` in its
#     stderr — the connection the pre-spawned listener holds, or one still
#     open) is closed the drained way (review R1): its writer is closed first
#     (for every such slot at once), then `_closeSlot drain` with ONE deadline
#     shared by the slots — nc sees stdin EOF and closes the socket cleanly, the
#     client gets EOF without a response (not an RST); a kill only past
#     now + CloseTimeout, so a Shutdown drains for at most one CloseTimeout;
#   * a slot that is only listening (or failed / empty): fds closed, killed at
#     once — closing its stdin would not end nc's accept, a drain there would
#     cost the whole CloseTimeout. Its relay sees its FIFO's EOF (the writer
#     is closed) and exits by itself; every FIFO, dropped or live, goes with
#     the dir, and the generation count starts again (launch L3.5-10).
TNetcatTransport.Shutdown() {
    local __ths_s __ths_fd __ths_pid __ths_ct="$CloseTimeout" __ths_dl
    local -a __ths_conn=()
    if ! kk.isInt "$__ths_ct" __ths_ct || (( __ths_ct < 0 )); then
        __ths_ct=2
    fi
    if [[ -n "$_dir" ]]; then
        for __ths_s in 0 1; do
            local -n __ths_pidS="_pid$__ths_s" __ths_wrS="_wr$__ths_s"
            if [[ -n "$__ths_pidS" ]]; then
                "$__inst__._state" "$__ths_s"
                if [[ "$RESULT" == connected ]]; then
                    __ths_conn+=("$__ths_s")
                    __ths_fd="$__ths_wrS"
                    __ths_wrS=""
                    if [[ -n "$__ths_fd" ]]; then
                        exec {__ths_fd}>&-
                    fi
                fi
            fi
        done
    fi
    if (( ${#__ths_conn[@]} )); then
        __ths_dl=$(( ${EPOCHREALTIME//[!0-9]/} + __ths_ct * 1000000 ))
        for __ths_s in "${__ths_conn[@]}"; do
            "$__inst__._closeSlot" "$__ths_s" drain "$__ths_dl"
        done
    fi
    for __ths_s in 0 1; do
        local -n __ths_rdS="_rd$__ths_s" __ths_wrS="_wr$__ths_s" __ths_pidS="_pid$__ths_s" __ths_seenS="_seen$__ths_s"
        __ths_fd="$__ths_wrS"
        if [[ -n "$__ths_fd" ]]; then
            exec {__ths_fd}>&-
        fi
        __ths_fd="$__ths_rdS"
        if [[ -n "$__ths_fd" ]]; then
            exec {__ths_fd}<&-
        fi
        __ths_pid="$__ths_pidS"
        if [[ -n "$__ths_pid" ]]; then
            ths._stopPid "$__ths_pid"
            wait "$__ths_pid" 2>/dev/null || :
        fi
        __ths_rdS=""
        __ths_wrS=""
        __ths_pidS=""
        __ths_seenS=""
    done
    _cur=0
    _inFd=""
    _outFd=""
    _firstLine=""
    _lineConsumed=0
    _timedOut=0
    _remoteAddress=""
    if [[ -n "$_dir" ]]; then
        rm -rf -- "$_dir" 2>/dev/null || :
        _dir=""
    fi
    _fifo0=""
    _fifo1=""
    _gen=0
    _made=0
    _dead=""
    return 0
}

build TNetcatTransport

# ths._v6short ADDR — REPLY = the IPv6 address ADDR in the RFC 5952 short form
# (lower case, no leading zeros, the longest run of two or more zero groups —
# the first of equal runs — as '::'). An ADDR that is not eight groups of hex
# digits (already short, dotted IPv4-mapped, …) is returned unchanged. An
# IPv4-mapped address written as eight groups comes out as `::ffff:7f00:1`,
# not RFC 5952's dotted `::ffff:127.0.0.1`. Fork-free.
ths._v6short() {
    local __ths_a="$1" __ths_g __ths_i __ths_bs=-1 __ths_bl=0 __ths_cs=-1 __ths_cl=0 __ths_r=""
    local -a __ths_v=()
    REPLY="$__ths_a"
    if [[ ! "$__ths_a" =~ ^[0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{1,4}){7}$ ]]; then
        return 0
    fi
    IFS=: read -r -a __ths_v <<< "$__ths_a"
    for (( __ths_i = 0; __ths_i < 8; __ths_i++ )); do
        printf -v __ths_g '%x' "$(( 16#${__ths_v[__ths_i]} ))"
        __ths_v[__ths_i]="$__ths_g"
        if [[ "$__ths_g" == 0 ]]; then
            if (( __ths_cs < 0 )); then
                __ths_cs=$__ths_i
                __ths_cl=0
            fi
            __ths_cl=$(( __ths_cl + 1 ))
            if (( __ths_cl > __ths_bl )); then
                __ths_bs=$__ths_cs
                __ths_bl=$__ths_cl
            fi
        else
            __ths_cs=-1
        fi
    done
    if (( __ths_bl < 2 )); then
        __ths_bs=-1
    fi
    for (( __ths_i = 0; __ths_i < 8; __ths_i++ )); do
        if (( __ths_i == __ths_bs )); then
            __ths_r+="::"
            __ths_i=$(( __ths_i + __ths_bl - 1 ))
            continue
        fi
        if [[ -n "$__ths_r" && "$__ths_r" != *:: ]]; then
            __ths_r+=":"
        fi
        __ths_r+="${__ths_v[__ths_i]}"
    done
    REPLY="$__ths_r"
    return 0
}

# ===========================================================================
# TSocatTransport — socat (>= 1.7.4) as the network backend (L2.7-N2, D2).
#
# The TNetcatTransport mechanism unchanged (two alternating slots, the FIFO +
# `cat` relay, the drained close, _spawn / _closeSlot / Accept /
# CloseConnection / Shutdown); only the listener's argv and the reading of
# its stderr differ:
#
#   SOCAT -d -d -lpsocat -t 0.5 TCP4-LISTEN:PORT,bind=ADDR,reuseaddr,accept-timeout=TTL STDIO
#   (TCP6-LISTEN:PORT,bind=[ADDR] when ADDR contains ':')
#
# `-lpsocat` fixes the program name in the log prefix (socat takes it from
# argv[0] otherwise: a binary named socat1 would log `socat1[PID]`). ADDR may
# only hold 0-9 A-Z a-z . : - (a ',' would add socat options).
#
# Without `fork`, socat accepts ONE connection and closes its listening socket
# (measured, docs/dev/launch/L2_triage.md §8) — the second slot is never
# bypassed. `accept-timeout` is the orphan TTL (the GNU `-w`). `-t 0.5`: after
# the server closes socat's stdin (CloseConnection), socat shuts the socket's
# write side and exits at the client's EOF, or 0.5 s later for a client that
# keeps the connection open (measured 514–847 ms on Ubuntu/Debian/Fedora,
# below CloseTimeout 2 s, so the drain never needs the kill).
#
# Its `-d -d` stderr lines are `YYYY/MM/DD HH:MM:SS socat[PID] S TEXT` (S =
# the severity letter; measured on socat 1.8.0.0 / 1.8.0.3 / 1.8.1.1 on
# Linux and 1.8.1.3 on FreeBSD, which writes `LEN=16 AF=2` for `AF=2` and
# `Operation timed out` for `Connection timed out`):
#   N listening on AF=2 127.0.0.1:PORT                      → listening
#   N accepting connection from AF=2 A:P on AF=2 …          → connected
#   W accept: Connection timed out                          → ttl (then exit 0)
#   E bind(5, {AF=2 …}, 16): Address already in use         → failed:TEXT
# NcBinary is inherited and unused; SocatBinary '' = $KCL_SOCAT, else `socat`
# on PATH.
# ===========================================================================
class TSocatTransport : TNetcatTransport
    public
        var SocatBinary
        constructor Create
        override func BuildArgv
        override func _state
end

TSocatTransport.Create() {
    inherited
    SocatBinary=""
}

# BuildArgv OUTARR — the listener's argv (above); RESULT = the element count.
# SOCAT = SocatBinary, else $KCL_SOCAT, else `socat` on PATH (ths._ncFind). rc
# 1 + LastError 'socat not found …' when there is none; rc 2 for an unusable
# OUTARR, Port outside 1–65535, ListenerTTL < 1, Address '' or with a
# character outside 0-9 A-Z a-z . : -, or a socat that fails the
# accept-timeout probe (LastError = the WHY of ths._backend).
TSocatTransport.BuildArgv() {
    local __ths_o="${1:-}" __ths_sb="$SocatBinary" __ths_port="$Port" __ths_ttl="$ListenerTTL" __ths_bk __ths_why
    if ! kk._outName "$__ths_o" __ths_ __THS_; then
        kk.debug "Error: TSocatTransport.BuildArgv: unusable output array name '$__ths_o'"
        kk._return ""
        return 2
    fi
    if ! kk.isInt "$__ths_port" __ths_port || (( __ths_port < 1 || __ths_port > 65535 )) \
       || ! kk.isInt "$__ths_ttl" __ths_ttl || (( __ths_ttl < 1 )) || [[ -z "$Address" ]]; then
        _lastError="TSocatTransport: Port must be 1-65535, ListenerTTL >= 1 and Address non-empty"
        kk.debug "Error: $_lastError"
        kk._return ""
        return 2
    fi
    # the address goes into socat's address string: a ',' or ':' option text
    # must never reach it (only host-name / IPv4 / IPv6 characters)
    if [[ "$Address" == *[!0-9A-Za-z.:-]* ]]; then
        _lastError="TSocatTransport: Address '$Address' may only contain 0-9 A-Z a-z . : -"
        kk.debug "Error: $_lastError"
        kk._return ""
        return 2
    fi
    if [[ -z "$__ths_sb" ]]; then
        __ths_sb="${KCL_SOCAT:-}"
    fi
    if [[ -z "$__ths_sb" ]]; then
        __ths_sb=socat
    fi
    ths._ncFind "$__ths_sb"
    __ths_sb="$__THS_NCPATH"
    if [[ "$__ths_sb" != */* || ! -f "$__ths_sb" || ! -x "$__ths_sb" ]]; then
        _lastError="socat not found (SocatBinary '$SocatBinary', KCL_SOCAT '${KCL_SOCAT:-}', PATH)"
        kk.debug "Error: TSocatTransport.BuildArgv: $_lastError"
        kk._return ""
        return 1
    fi
    # the identity check of THIS socat (precedence b; KCL_NC blanked for the
    # call, or an explicit netcat would answer instead)
    KCL_NC="" ths._backend "" "$__ths_sb"
    __ths_bk="$__THS_BACKEND"
    __ths_why="$__THS_BACKEND_WHY"
    if [[ "$__ths_bk" != socat ]]; then
        _lastError="$__ths_why"
        kk.debug "Error: TSocatTransport.BuildArgv: $_lastError"
        kk._return ""
        return 2
    fi
    local -n __ths_out="$__ths_o"
    if [[ "$Address" == *:* ]]; then
        __ths_out=("$__ths_sb" -d -d -lpsocat -t 0.5 "TCP6-LISTEN:$__ths_port,bind=[$Address],reuseaddr,accept-timeout=$__ths_ttl" STDIO)
    else
        __ths_out=("$__ths_sb" -d -d -lpsocat -t 0.5 "TCP4-LISTEN:$__ths_port,bind=$Address,reuseaddr,accept-timeout=$__ths_ttl" STDIO)
    fi
    kk._return "${#__ths_out[@]}"
    return 0
}

# _state SLOT — as TNetcatTransport._state, from socat's `-d -d` lines
# (fork-free): RESULT = listening | connected | ttl | failed:<the text after
# the severity letter of the first E/F line> | none; REPLY = the remote 'A:P'
# when connected ('[A]:P' for IPv6, A in the RFC 5952 short form: socat prints
# all eight groups). Precedence as the base: connected, then ttl, then failed
# (an E line after the timeout never wins). Every other line is ignored.
# Public: an override called from the base's Accept / Shutdown frames would
# print a kklass visibility warning as private or protected (measured).
TSocatTransport._state() {
    local __ths_f="$_dir/err$1" __ths_l __ths_st=none __ths_first="" __ths_conn="" __ths_ttl=0 __ths_m
    REPLY=""
    if [[ ! -f "$__ths_f" ]]; then
        kk._return none
        return 0
    fi
    while IFS= read -r __ths_l || [[ -n "$__ths_l" ]]; do
        __ths_l="${__ths_l%"$__THS_CR"}"
        if [[ "$__ths_l" != *" socat["*"] "?" "* ]]; then
            continue
        fi
        __ths_m="${__ths_l#* socat\[*\] }"
        case "$__ths_m" in
            'N listening on '*)
                __ths_st=listening ;;
            'N accepting connection from '*'AF='*' on '*)
                # the BSD form puts the sockaddr length first: LEN=16 AF=2 A:P
                __ths_m="${__ths_m#N accepting connection from }"
                if [[ "$__ths_m" == LEN=* ]]; then
                    __ths_m="${__ths_m#* }"
                fi
                __ths_m="${__ths_m#AF=* }"
                __ths_conn="${__ths_m%% on *}" ;;
            'W accept: Connection timed out' | 'W accept: Operation timed out')
                # ETIMEDOUT as Linux / FreeBSD spell it
                __ths_ttl=1 ;;
            [EF]' '*)
                if [[ -z "$__ths_first" ]]; then
                    __ths_first="${__ths_m:2}"
                fi ;;
        esac
    done < "$__ths_f"
    if [[ -n "$__ths_conn" ]]; then
        if [[ "$__ths_conn" == '['*']:'* ]]; then
            __ths_m="${__ths_conn#\[}"
            ths._v6short "${__ths_m%%\]*}"
            __ths_conn="[$REPLY]:${__ths_conn##*\]:}"
        fi
        REPLY="$__ths_conn"
        kk._return connected
    elif (( __ths_ttl )); then
        kk._return ttl
    elif [[ -n "$__ths_first" ]]; then
        kk._return "failed:$__ths_first"
    else
        kk._return "$__ths_st"
    fi
    return 0
}

build TSocatTransport

# ===========================================================================
# THttpServer (PLAN §1.3, §2.6). The handlers run in the server's OWN shell:
# objects live across requests. Only the listener nc is spawned per
# connection.
#
#   Serve       BeginServe; ServeOne until Terminate / Active = false / a
#               signal / MaxRequests; EndServe. rc 0, or rc 1 on a transport
#               fatal (LastError). Active = true does the same (as FPC).
#   BeginServe  validates the numbers (kk.isInt; rc 2), saves the traps, PIPE
#               ignored, INT/TERM → __THS_SIGNAL; Transport '' → an OWNED
#               transport ${inst}_tr with the server's Address/Port: a
#               TSocatTransport when ths._backend says socat, else a
#               TNetcatTransport; a backend `none` is refused (rc 2, LastError
#               = the WHY) before any trap is touched.
#   ServeOne    accept + handle ONE connection: rc 0 handled (RESULT = the
#               code answered, or `gone`) · 1 idle tick / a client that left /
#               a signal · 2 fatal (LastError). RequestCount + 1 for every
#               ANSWERED connection (a 408 included) — never for `gone`, so
#               gone probes do not use up MaxRequests (review F3). On rc 1
#               without a signal it fires OnAcceptIdle SERVER (P3: the event
#               moved here from Serve's loop, so THttpApplication.DoRun gets
#               it too).
#   Stopping    1 once Terminate / Active = false / a signal asked the server
#               to stop (read-only; THttpApplication.DoRun reads it, P3).
#   EndServe    transport Shutdown, the owned transport freed, the saved traps
#               restored exactly (`trap - INT TERM PIPE; eval "$saved"`).
#
# One connection (_handleConnection, protected): fresh ${inst}_req /
# ${inst}_resp (a stale pair from an aborted pass is deleted first) →
# TimedOut ? 408 : ReadFrom (FIRSTLINE, REMOTE, CONSUMED = the transport's
# LineConsumed — review F5) → ISHEAD from REQ.Method (kept after a later-stage
# status — review F4; the FirstLine prefix only when Method is '') → a
# status is sent as the Code, `gone` sends nothing → else
# $inst.HandleRequest (VIRTUAL: OnRequest, else Router.RouteRequest, else 404)
# → a handler rc ≠ 0 with nothing sent: OnRequestError REQ RESP RC, then
# (unless it sent) a FRESH 500 response — the handler's partial Content and
# headers are dropped → SendContent unless sent → OnLog SERVER 'ADDR METHOD
# URI CODE BYTES MS' (empty → '-', control characters → '?', BYTES = body
# bytes sent, MS by the owned TStopwatch ${inst}_sw; METHOD and URI are '-'
# only when the request line did not parse) → CloseConnection → both deleted
# → RequestCount + 1 unless gone.
#
# THE PROPERTY RULE (§1.3). RequestCount, LastError, Active, MaxRequests and
# Stopping (the application reads the last two, P3) are properties. The other
# fields are plain vars: written from outside (`S.Port = 8080` does not
# print), read only by the server's own bodies. Handlers run inside the server's frames, where
# every field is a nameref: a handler declares its variables `local` (C25).
# ===========================================================================
class THttpServer
    public
        var Address
        var Port
        var Transport
        var Router
        var OnRequest
        var OnRequestError
        var OnAcceptIdle
        var OnLog
        var AcceptIdleTimeout
        var RequestTimeout
        var MaxContentLength
        property MaxRequests  read MaxRequests write MaxRequests
        var ServerBanner
        property RequestCount read _requestCount
        property LastError    read _lastError
        property Stopping     read _stop
        property Active       read GetActive write SetActive
        constructor Create
        destructor  Destroy
        func GetActive
        proc SetActive
        proc Serve
        proc BeginServe
        func ServeOne
        proc EndServe
        proc Terminate
        proc HandleRequest
    protected
        proc _handleConnection
        proc _log
    private
        var _active
        var _stop
        var _requestCount
        var _lastError
        var _ownsTransport
        var _savedTraps
        proc _onSignal
end

THttpServer.Create() {
    local __ths_v="${__inst__}_sw_class"
    Address=127.0.0.1
    Port=8080
    Transport=""
    Router=""
    OnRequest=""
    OnRequestError=""
    OnAcceptIdle=""
    OnLog=""
    AcceptIdleTimeout=0
    RequestTimeout=10
    MaxContentLength=65536
    MaxRequests=0
    ServerBanner="$__THS_BANNER"
    _active=0
    _stop=0
    _requestCount=0
    _lastError=""
    _ownsTransport=0
    _savedTraps=""
    if [[ -n "${!__ths_v:-}" ]]; then
        "${__inst__}_sw.delete"
    fi
    TStopwatch.new "${__inst__}_sw"
}

THttpServer.Destroy() {
    local __ths_v
    if [[ "$_active" == 1 ]]; then
        kk.call_silent "$__inst__" EndServe
    fi
    if [[ "$_ownsTransport" == 1 && -n "$Transport" ]] && declare -F "$Transport.delete" >/dev/null; then
        "$Transport.delete"
    fi
    for __ths_v in "${__inst__}_req" "${__inst__}_resp"; do
        if declare -F "$__ths_v.delete" >/dev/null; then
            "$__ths_v.delete"
        fi
    done
    if declare -F "${__inst__}_sw.delete" >/dev/null; then
        "${__inst__}_sw.delete"
    fi
}

# Active — 1 while serving (between BeginServe and EndServe).
THttpServer.GetActive() {
    kk._return "$_active"
    return 0
}

# SetActive true|1 → Serve (blocks; rc 1 if already active) · false|0 →
# Terminate (the current response is still sent). Anything else rc 2.
THttpServer.SetActive() {
    local __ths_v="${1:-}"
    if [[ "$__ths_v" == 1 || "$__ths_v" == true || "$__ths_v" == True || "$__ths_v" == TRUE ]]; then
        if [[ "$_active" == 1 ]]; then
            kk.debug "Error: THttpServer.SetActive: already active"
            return 1
        fi
        "$__inst__.Serve"
        return
    fi
    if [[ "$__ths_v" == 0 || "$__ths_v" == false || "$__ths_v" == False || "$__ths_v" == FALSE ]]; then
        if [[ "$_active" == 1 ]]; then
            "$__inst__.Terminate"
        fi
        return 0
    fi
    kk.debug "Error: THttpServer.SetActive: '$__ths_v' is not true/false"
    return 2
}

# Serve — BeginServe, then ServeOne until stopped, then EndServe (PLAN §2.6).
# rc 0 (Terminate, Active = false, MaxRequests, INT/TERM) · rc 1 transport
# fatal (LastError) · BeginServe's own rc 1/2 when it refuses.
THttpServer.Serve() {
    local __ths_rc=0 __ths_r=0
    "$__inst__.BeginServe" || return $?
    while :; do
        if [[ -n "$__THS_SIGNAL" ]]; then
            "$__inst__._onSignal"
        fi
        if [[ "$_stop" == 1 ]]; then
            break
        fi
        if (( MaxRequests > 0 && _requestCount >= MaxRequests )); then
            break
        fi
        __ths_r=0
        "$__inst__.ServeOne" || __ths_r=$?
        if (( __ths_r == 2 )); then
            __ths_rc=1
            break
        fi
    done
    "$__inst__.EndServe"
    return "$__ths_rc"
}

# BeginServe — rc 1 if already active; rc 2 (nothing changed) for a number
# that is not an integer >= 0 (RequestTimeout >= 1) or a Transport that is not
# a THttpTransport instance.
THttpServer.BeginServe() {
    local __ths_bad="" __ths_n __ths_v __ths_bk=""
    if [[ "$_active" == 1 ]]; then
        kk.debug "Error: THttpServer.BeginServe: already serving"
        return 1
    fi
    if kk.isInt "$AcceptIdleTimeout" __ths_n && (( __ths_n >= 0 )); then AcceptIdleTimeout="$__ths_n"; else __ths_bad+=" AcceptIdleTimeout"; fi
    if kk.isInt "$RequestTimeout" __ths_n && (( __ths_n >= 1 )); then RequestTimeout="$__ths_n"; else __ths_bad+=" RequestTimeout"; fi
    if kk.isInt "$MaxContentLength" __ths_n && (( __ths_n >= 0 )); then MaxContentLength="$__ths_n"; else __ths_bad+=" MaxContentLength"; fi
    if kk.isInt "$MaxRequests" __ths_n && (( __ths_n >= 0 )); then MaxRequests="$__ths_n"; else __ths_bad+=" MaxRequests"; fi
    if [[ -n "$Transport" ]]; then
        __ths_v="${Transport}_class"
        if [[ ! "$Transport" =~ $__THS_NAME_RE ]] || ! kk.derivesFrom "${!__ths_v:-}" THttpTransport; then
            __ths_bad+=" Transport"
        fi
    fi
    if [[ -n "$__ths_bad" ]]; then
        _lastError="THttpServer.BeginServe: bad value of${__ths_bad}"
        kk.debug "Error: $_lastError"
        return 2
    fi
    if [[ -z "$Transport" ]]; then
        ths._backend
        __ths_bk="$__THS_BACKEND"
        __ths_v="$__THS_BACKEND_WHY"
        if [[ "$__ths_bk" == none ]]; then
            _lastError="$__ths_v"
            kk.debug "Error: THttpServer.BeginServe: $_lastError"
            return 2
        fi
    fi
    _savedTraps="$(trap -p INT TERM PIPE)"
    __THS_SIGNAL=""
    trap '' PIPE
    trap '__THS_SIGNAL=INT' INT
    trap '__THS_SIGNAL=TERM' TERM
    if [[ -z "$Transport" ]]; then
        __ths_v="${__inst__}_tr_class"
        if [[ -n "${!__ths_v:-}" ]]; then
            "${__inst__}_tr.delete"
        fi
        # the factory (L2.7-N2): socat → TSocatTransport; gnu, and missing
        # (whose Accept then reports 'nc not found …'), → TNetcatTransport
        if [[ "$__ths_bk" == socat ]]; then
            TSocatTransport.new "${__inst__}_tr"
        else
            TNetcatTransport.new "${__inst__}_tr"
        fi
        "${__inst__}_tr.Address" = "$Address"
        "${__inst__}_tr.Port" = "$Port"
        Transport="${__inst__}_tr"
        _ownsTransport=1
    fi
    _stop=0
    _requestCount=0
    _lastError=""
    _active=1
    return 0
}

# ServeOne — accept and handle ONE connection (see the class comment). Works
# without BeginServe when Transport is set (no trap handling then).
THttpServer.ServeOne() {
    local __ths_tr="$Transport" __ths_r=0 __ths_code
    if [[ -z "$__ths_tr" || ! "$__ths_tr" =~ $__THS_NAME_RE ]] || ! declare -F "$__ths_tr.Accept" >/dev/null; then
        _lastError="THttpServer.ServeOne: no transport (BeginServe first, or set Transport)"
        kk.debug "Error: $_lastError"
        kk._return ""
        return 2
    fi
    if [[ -n "$__THS_SIGNAL" ]]; then
        "$__inst__._onSignal"
        kk._return ""
        return 1
    fi
    "$__ths_tr.Accept" "$AcceptIdleTimeout" "$RequestTimeout" || __ths_r=$?
    if (( __ths_r == 1 )); then
        if [[ -n "$__THS_SIGNAL" ]]; then
            "$__inst__._onSignal"
        elif [[ "$_stop" != 1 && -n "$OnAcceptIdle" ]]; then
            # The idle event lives here, not in Serve's loop (P3), so every
            # driver of ServeOne — Serve, THttpApplication.DoRun, a caller's
            # own loop — gets it.
            if ths._hookOk "$OnAcceptIdle"; then
                "$OnAcceptIdle" "$__inst__" || :
            else
                kk.debug "Error: THttpServer.ServeOne: OnAcceptIdle '$OnAcceptIdle' is not a defined handler"
            fi
        fi
        kk._return ""
        return 1
    fi
    if (( __ths_r != 0 )); then
        "$__ths_tr.LastError"
        _lastError="$RESULT"
        if [[ -z "$_lastError" ]]; then
            _lastError="THttpServer.ServeOne: the transport's Accept failed (rc $__ths_r)"
        fi
        kk._return ""
        return 2
    fi
    "$__inst__._handleConnection"
    __ths_code="$RESULT"
    # A `gone` connection (the client left, nothing sent, nothing logged) is
    # not a request: it does not count, so gone probes cannot use up
    # MaxRequests (review F3). A 408 and every other answer count.
    if [[ "$__ths_code" != gone ]]; then
        _requestCount=$(( _requestCount + 1 ))
    fi
    kk._return "$__ths_code"
    return 0
}

# _handleConnection — one accepted connection, from the objects to the close
# (protected: a descendant server may call it). RESULT = the code answered, or
# `gone`.
THttpServer._handleConnection() {
    local __ths_tr="$Transport" __ths_req="${__inst__}_req" __ths_resp="${__inst__}_resp"
    local __ths_in __ths_out __ths_fl __ths_lc __ths_to __ths_ra __ths_st __ths_head=0 __ths_hrc=0 __ths_v
    local __ths_m="" __ths_u="" __ths_code __ths_b=0 __ths_ms="" __ths_rt="$RequestTimeout" __ths_max="$MaxContentLength"
    if ! kk.isInt "$__ths_rt" __ths_rt || (( __ths_rt < 1 )); then
        __ths_rt=10
    fi
    if ! kk.isInt "$__ths_max" __ths_max || (( __ths_max < 0 )); then
        __ths_max=65536
    fi
    for __ths_v in "$__ths_req" "$__ths_resp"; do
        if declare -F "$__ths_v.delete" >/dev/null; then
            "$__ths_v.delete"
        fi
    done
    "${__inst__}_sw.Restart"
    "$__ths_tr.InFd";          __ths_in="$RESULT"
    "$__ths_tr.OutFd";         __ths_out="$RESULT"
    "$__ths_tr.FirstLine";     __ths_fl="$RESULT"
    "$__ths_tr.LineConsumed";  __ths_lc="$RESULT"
    "$__ths_tr.TimedOut";      __ths_to="$RESULT"
    "$__ths_tr.RemoteAddress"; __ths_ra="$RESULT"
    THttpRequest.new "$__ths_req"
    THttpResponse.new "$__ths_resp"
    if [[ "$__ths_to" == 1 ]]; then
        __ths_st=408
    else
        # CONSUMED from the transport (review F5): a consumed EMPTY line is
        # the request line (→ 400), never "nothing consumed".
        if "$__ths_req.ReadFrom" "$__ths_in" $(( ${EPOCHREALTIME//[!0-9]/} + __ths_rt * 1000000 )) "$__ths_max" "$__ths_fl" "$__ths_ra" "$__ths_lc"; then
            __ths_st="$RESULT"
        else
            __ths_st=500
        fi
    fi
    # ISHEAD from the request's own Method, which ReadFrom keeps once the
    # request line parsed, whatever a later stage returned (review F4). Only
    # when there is none — a status from the request line itself, a 408
    # without ReadFrom — the transport's FirstLine prefix is the hint (''
    # under TReplayTransport).
    "$__ths_req.Method"
    __ths_m="$RESULT"
    if [[ "$__ths_m" == HEAD ]] || [[ -z "$__ths_m" && "$__ths_fl" == 'HEAD '* ]]; then
        __ths_head=1
    fi
    "$__ths_resp.Attach" "$__ths_out" "$__ths_head" "$ServerBanner" || :
    if [[ "$__ths_st" != 0 && "$__ths_st" != gone ]]; then
        "$__ths_resp.Code" = "$__ths_st"
    elif [[ "$__ths_st" == 0 ]]; then
        "$__inst__.HandleRequest" "$__ths_req" "$__ths_resp" || __ths_hrc=$?
        if (( __ths_hrc != 0 )); then
            "$__ths_resp.ContentSent"
            if [[ "$RESULT" != 1 ]]; then
                if [[ -n "$OnRequestError" ]]; then
                    if ths._hookOk "$OnRequestError"; then
                        "$OnRequestError" "$__ths_req" "$__ths_resp" "$__ths_hrc" || :
                    else
                        kk.debug "Error: THttpServer: OnRequestError '$OnRequestError' is not a defined handler"
                    fi
                fi
                "$__ths_resp.ContentSent"
                if [[ "$RESULT" != 1 ]]; then
                    "$__ths_resp.delete"
                    THttpResponse.new "$__ths_resp"
                    "$__ths_resp.Attach" "$__ths_out" "$__ths_head" "$ServerBanner" || :
                    "$__ths_resp.Code" = 500
                fi
            fi
        fi
    fi
    if [[ "$__ths_st" == gone ]]; then
        __ths_code=gone
    else
        "$__ths_resp.ContentSent"
        if [[ "$RESULT" != 1 ]]; then
            "$__ths_resp.SendContent" || :
        fi
        "$__ths_req.Method";  __ths_m="$RESULT"
        "$__ths_req.URI";     __ths_u="$RESULT"
        "$__ths_resp.Code";   __ths_code="$RESULT"
        if [[ -n "$__ths_code" && "$__ths_code" != *[!0-9]* && "$__ths_head" == 0 ]] \
           && (( 10#$__ths_code >= 200 && 10#$__ths_code != 204 && 10#$__ths_code != 304 )); then
            "$__ths_resp.Content"
            ths._bytes "$RESULT"
        fi
        "${__inst__}_sw.elapsedMilliseconds"
        __ths_ms="$RESULT"
        "$__inst__._log" "$__ths_ra" "$__ths_m" "$__ths_u" "$__ths_code" "$__ths_b" "$__ths_ms"
    fi
    "$__ths_tr.CloseConnection" || :
    "$__ths_req.delete"
    "$__ths_resp.delete"
    kk._return "$__ths_code"
    return 0
}

# EndServe — idempotent; rc 0.
THttpServer.EndServe() {
    local __ths_v
    if [[ "$_active" != 1 ]]; then
        return 0
    fi
    for __ths_v in "${__inst__}_req" "${__inst__}_resp"; do
        if declare -F "$__ths_v.delete" >/dev/null; then
            "$__ths_v.delete"
        fi
    done
    if [[ -n "$Transport" ]] && declare -F "$Transport.Shutdown" >/dev/null; then
        "$Transport.Shutdown" || :
    fi
    if [[ "$_ownsTransport" == 1 ]]; then
        if declare -F "$Transport.delete" >/dev/null; then
            "$Transport.delete"
        fi
        Transport=""
        _ownsTransport=0
    fi
    trap - INT TERM PIPE
    eval "$_savedTraps"
    _savedTraps=""
    __THS_SIGNAL=""
    _active=0
    return 0
}

# Terminate — stop after the current request (the response is still sent).
THttpServer.Terminate() {
    _stop=1
    return 0
}

# HandleRequest REQ RESP — VIRTUAL: OnRequest wins, else Router.RouteRequest,
# else 404. Returns the handler's rc (a non-zero one with nothing sent becomes
# 500 in _handleConnection). A descendant overrides it and passes the
# arguments on: `inherited HandleRequest "$@"` (bare `inherited` in a method
# passes none, C8).
THttpServer.HandleRequest() {
    if [[ -n "$OnRequest" ]]; then
        if ! ths._hookOk "$OnRequest"; then
            kk.debug "Error: THttpServer.HandleRequest: OnRequest '$OnRequest' is not a defined handler"
            return 2
        fi
        "$OnRequest" "$1" "$2"
        return
    fi
    if [[ -n "$Router" ]]; then
        if [[ ! "$Router" =~ $__THS_NAME_RE ]] || ! declare -F "$Router.RouteRequest" >/dev/null; then
            kk.debug "Error: THttpServer.HandleRequest: Router '$Router' is not a THttpRouter instance"
            return 2
        fi
        "$Router.RouteRequest" "$1" "$2"
        return
    fi
    "$2.Code" = 404
    return 0
}

# _log ADDR METHOD URI CODE BYTES MS — one access-log line to OnLog SERVER
# LINE: the six fields joined by one space, an empty field as '-', every
# control character as '?'. Protected: a descendant may log its own lines.
THttpServer._log() {
    local __ths_line="" __ths_f
    if [[ -z "$OnLog" ]]; then
        return 0
    fi
    for __ths_f in "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}"; do
        if [[ -z "$__ths_f" ]]; then
            __ths_f=-
        fi
        __ths_line+=" ${__ths_f//[[:cntrl:]]/?}"
    done
    if ths._hookOk "$OnLog"; then
        "$OnLog" "$__inst__" "${__ths_line# }" || :
    else
        kk.debug "Error: THttpServer: OnLog '$OnLog' is not a defined handler"
    fi
    return 0
}

# _onSignal — the INT/TERM handling, run by the loop at a safe point once the
# trap set __THS_SIGNAL: stop, and shut the transport down (a connection the
# pre-spawned listener holds is closed without a response).
THttpServer._onSignal() {
    _stop=1
    if [[ -n "$Transport" ]] && declare -F "$Transport.Shutdown" >/dev/null; then
        "$Transport.Shutdown" || :
    fi
    return 0
}

build THttpServer
