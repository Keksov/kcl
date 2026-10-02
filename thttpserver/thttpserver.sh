#!/bin/bash
# thttpserver.sh — the entry point of kcl/thttpserver (PLAN.md §1.2).
#
# Sources thttpmessage.sh (THttpRequest, THttpResponse), thttprouter.sh
# (THttpRouteObject, THttpRouter) and kcl/tstopwatch (the access-log timing).
# Own content: the transport seam — THttpTransport (abstract), TReplayTransport
# (the fork-free test double), TNetcatTransport (GNU netcat 0.7.1, two
# alternating listener slots) — and THttpServer.
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

# Re-source guard (kcl README §1.4).
if [[ -n "${_THS_THTTPSERVER_SOURCED:-}" ]]; then
    return
fi
declare -g _THS_THTTPSERVER_SOURCED=1

# Locale self-heal (kcl README §1.6).
if [[ -z "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" ]]; then
    export LC_CTYPE=C.UTF-8
fi

THTTPSERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$THTTPSERVER_DIR/../../kklass/kklass_pascal.sh"
source "$THTTPSERVER_DIR/thttpmessage.sh"
source "$THTTPSERVER_DIR/thttprouter.sh"
source "$THTTPSERVER_DIR/../tstopwatch/tstopwatch.sh"

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
# the first Accept, removed by Shutdown). The mechanism is the P2 spike's,
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
#     CloseTimeout → close rd → kill ONLY past that deadline → wait (C2).
# nc's exit status is always 1: the state comes from its -vv stderr —
# `Listening on` (bound), `Connection from A:P` (accepted), `Listen mode
# failed: Connection timed out` (-w expired: respawn), anything else (bind
# failure, exec failure, …) is fatal: Accept rc 2 with LastError = that line,
# never a silent respawn loop (C6). `-w ListenerTTL` limits accept only: it is
# an orphan time-to-live, not a request timeout (C5).
#
# Per-request forks: the listener spawn only (fork + cat relay + nc, ≈35–45
# ms, synchronous). mktemp/mkfifo once per dir, rm once per Shutdown.
# FD HYGIENE: a background process a handler starts inherits the current
# connection's writer and holds the connection open until CloseTimeout.
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
        proc _spawn
        proc _closeSlot
        func _state
end

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
    local __ths_o="${1:-}" __ths_nc="$NcBinary" __ths_p __ths_d __ths_port="$Port" __ths_ttl="$ListenerTTL"
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
    if [[ "$__ths_nc" != */* || ! -f "$__ths_nc" || ! -x "$__ths_nc" ]]; then
        _lastError="nc not found (NcBinary '$NcBinary', KCL_NC '${KCL_NC:-}', PATH)"
        kk.debug "Error: TNetcatTransport.BuildArgv: $_lastError"
        kk._return ""
        return 1
    fi
    local -n __ths_out="$__ths_o"
    __ths_out=("$__ths_nc" -l -c -vv -n -w "$__ths_ttl" -s "$Address" -p "$__ths_port")
    kk._return "${#__ths_out[@]}"
    return 0
}

# _spawn SLOT — start SLOT's listener (PLAN §2.5): the err file truncated, nc
# started through a process substitution whose child closes the OTHER slot's
# fds first, its stdin fed from the slot FIFO through `cat`, its -vv stderr to
# the slot's err file; then the O_WRONLY writer (the open pairs with the
# relay's and returns once it ran). rc 1 (LastError set) if no argv or no
# child could be started.
TNetcatTransport._spawn() {
    local __ths_s="$1" __ths_dir="$_dir" __ths_rd="" __ths_wr="" __ths_wo __ths_ro __ths_pid
    local -a ths_argv=()
    if ! "$__inst__.BuildArgv" ths_argv; then
        return 1
    fi
    local -n __ths_rdS="_rd$__ths_s" __ths_wrS="_wr$__ths_s" __ths_pidS="_pid$__ths_s" __ths_seenS="_seen$__ths_s"
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
                exec "${ths_argv[@]}" <"$__ths_dir/fifo$__ths_s" 2>"$__ths_dir/err$__ths_s"
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
                exec "${ths_argv[@]}" < <(exec cat "$__ths_dir/fifo$__ths_s" 2>/dev/null) 2>"$__ths_dir/err$__ths_s"
            ); then
            _lastError="TNetcatTransport: cannot start the listener"
            kk.debug "Error: $_lastError"
            return 1
        fi
    fi
    __ths_pid=$!
    exec {__ths_wr}>"$__ths_dir/fifo$__ths_s"
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
TNetcatTransport._closeSlot() {
    local __ths_s="$1" __ths_mode="${2:-drain}" __ths_rd __ths_wr __ths_pid __ths_eof=0
    local __ths_x __ths_r __ths_left __ths_dl __ths_ct="$CloseTimeout"
    local -n __ths_rdS="_rd$__ths_s" __ths_wrS="_wr$__ths_s" __ths_pidS="_pid$__ths_s" __ths_seenS="_seen$__ths_s"
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
            kill -TERM "$__ths_pid" 2>/dev/null || :
        fi
        wait "$__ths_pid" 2>/dev/null || :
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
        if [[ -z "$_dir" ]] || ! mkfifo "$_dir/fifo0" "$_dir/fifo1" 2>/dev/null; then
            if [[ -n "$_dir" ]]; then
                rm -rf -- "$_dir" 2>/dev/null || :
            fi
            _dir=""
            _lastError="TNetcatTransport: cannot create the temp dir / FIFOs under '${TMPDIR:-/tmp}'"
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
#     cost the whole CloseTimeout.
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
            kill -TERM "$__ths_pid" 2>/dev/null || :
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
    return 0
}

build TNetcatTransport

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
#               TNetcatTransport ${inst}_tr with the server's Address/Port.
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
    local __ths_bad="" __ths_n __ths_v
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
        TNetcatTransport.new "${__inst__}_tr"
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
