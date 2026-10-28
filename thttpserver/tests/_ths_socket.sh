#!/usr/bin/env bash
# _ths_socket.sh — shared helpers of the socket tests (004, 005, 007; P3: 006,
# 009 through ths_launch / ths_reap). Not a test file (no NNN_ prefix):
# sourced by them after ktest.sh.
#
# The socket-test rules (PLAN §4, timing lessons, C22):
#   * the server is a CHILD bash under `timeout` with a guard of 180 s, its
#     stdout/stderr always redirected to files (the runner captures every test
#     file with $( … 2>&1 ) and waits for each holder of that stdout);
#   * the child ends on its own: MaxRequests where the count is exact, and in
#     every server an OnAcceptIdle budget — the test touches `done` and the next
#     idle tick calls Terminate; with no request for IDLE_BUDGET ticks the
#     server terminates by itself, so a failed client never costs the guard;
#   * ports: 20000 + (BASHPID*7919 + RANDOM) % 20000, a new port on a bind
#     failure; every curl has --noproxy '*' and -m; a client retries ONLY on
#     curl rc 7 / a refused /dev/tcp connect; all proxy variables are unset;
#   * ordering is event-driven: marker files polled in bounded loops (the
#     sleep inside is the poll interval, never a synchronisation by itself);
#   * the backend is the unit's own choice (ths._backend, L2.7-N1/N2): GNU
#     netcat, else socat. THS_NC = KCL_NC, else `nc` on PATH, else
#     /c/bin/msys64/usr/bin/nc.exe — only that msys fallback (or a KCL_NC the
#     caller set) reaches the detection and the child as KCL_NC; otherwise
#     KCL_NC stays unset and the detection is automatic (a Linux with
#     OpenBSD nc on PATH and socat installed runs on socat). With no usable
#     backend the socket cases SKIP visibly (kt_test_pass "SKIP: …"), so the
#     case count stays the same.

unset -v HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy FTP_PROXY ftp_proxy

# the process table (kt_proc_snapshot) for ths_children_pids/_of/ths_child_of
[[ -n ${_KT_PROC_SOURCED:-} ]] || source "${BASH_SOURCE[0]%/*}/../../../ktests/ktest_proc.sh"

# ths._backend (the netcat identification) lives in the unit: 005 and 009 do
# not load it themselves.
if ! declare -F ths._backend >/dev/null; then
    source "${UNIT:-$UNIT_DIR/thttpserver.sh}"
fi

# THS_NC — the netcat the children may use; THS_NC_ENV — 1 when it must reach
# the detection and the child through KCL_NC (set by the caller, or not found
# on PATH: the msys fallback).
THS_NC="${KCL_NC:-}"
THS_NC_ENV=0
if [[ -n "$THS_NC" ]]; then
    THS_NC_ENV=1
elif THS_NC="$(command -v nc 2>/dev/null)" && [[ -n "$THS_NC" ]]; then
    THS_NC_ENV=0
elif [[ -x /c/bin/msys64/usr/bin/nc.exe ]]; then
    THS_NC=/c/bin/msys64/usr/bin/nc.exe
    THS_NC_ENV=1
else
    THS_NC=""
fi

# ths_have_backend — rc 0 when the unit's own detection (ths._backend) finds
# a usable backend, gnu or socat. KCL_NC=$THS_NC for that call ONLY when
# THS_NC_ENV=1; otherwise KCL_NC stays unset (automatic detection). The result
# is copied at once into THS_BACKEND / THS_BACKEND_WHY (every later
# ths._backend call — BuildArgv's identity check included — overwrites the
# __THS_* globals).
THS_BACKEND=""
THS_BACKEND_WHY=""
ths_have_backend() {
    if (( THS_NC_ENV )); then
        KCL_NC=$THS_NC ths._backend
    else
        ths._backend
    fi
    THS_BACKEND="$__THS_BACKEND"
    THS_BACKEND_WHY="$__THS_BACKEND_WHY"
    [[ "$THS_BACKEND" == gnu || "$THS_BACKEND" == socat ]]
}

# ths_have_nc — rc 0 when the socket cases can run.
ths_have_nc() { ths_have_backend; }

# ths_skip TITLE… — one visible SKIP case per title (the case count is kept).
ths_skip() {
    local t why
    if [[ -z "$THS_BACKEND" ]]; then
        ths_have_backend || :
    fi
    why="$THS_BACKEND_WHY"
    if [[ "$THS_BACKEND" == missing ]]; then
        why="no netcat: $why"
    fi
    for t in "$@"; do
        kt_test_start "$t"
        kt_test_pass "SKIP: $why"
    done
}

ths_nport() { THS_PORT=$(( 20000 + (BASHPID * 7919 + RANDOM) % 20000 )); }

# ths_ticks_ge N — the server under THS_DIR has counted at least N idle ticks
# since its last request.
ths_ticks_ge() {
    local t=""
    { read -r t < "$THS_DIR/ticks"; } 2>/dev/null || return 1
    [[ "$t" =~ ^[0-9]+$ ]] && (( t >= $1 ))
}

# ths_poll SECONDS CMD… — run CMD every 50 ms until it succeeds; rc 1 on timeout.
ths_poll() {
    local n=$(( $1 * 20 )) i
    shift
    for (( i = 0; i < n; i++ )); do
        if "$@"; then return 0; fi
        sleep 0.05
    done
    return 1
}

# ths_mark — THS_RE_BOUND / THS_RE_BINDFAIL / THS_RE_CONN (ERE) from the
# backend (THS_BACKEND; detected first when empty): the listener's stderr line
# that says "bound", the line (= LastError) of a bind failure, and the line of
# an accepted connection. socat's lines start with a timestamp: unanchored
# (measured, L2.7-N2 step 0). Neither backend: patterns that never match.
ths_mark() {
    if [[ -z "$THS_BACKEND" ]]; then
        ths_have_backend || :
    fi
    case "$THS_BACKEND" in
        gnu)
            THS_RE_BOUND='^Listening on'
            THS_RE_BINDFAIL="Couldn't setup listening socket"
            THS_RE_CONN='^Connection from' ;;
        socat)
            THS_RE_BOUND=' N listening on '
            THS_RE_BINDFAIL='bind\(.*Address (already )?in use'   # glibc / musl
            THS_RE_CONN=' N accepting connection from ' ;;
        *)
            THS_RE_BOUND='a^b'
            THS_RE_BINDFAIL='a^b'
            THS_RE_CONN='a^b' ;;
    esac
}

# ths_new_transport NAME — a transport instance NAME for the detected backend:
# TSocatTransport for socat, else TNetcatTransport (NcBinary = THS_NC when
# THS_NC_ENV=1).
ths_new_transport() {
    ths_mark
    if [[ "$THS_BACKEND" == socat ]]; then
        TSocatTransport.new "$1"
    else
        TNetcatTransport.new "$1"
        if (( THS_NC_ENV )); then
            "$1.NcBinary" = "$THS_NC"
        fi
    fi
}

# ths_listen_argv OUTARR PORT TTL — the detected backend's listener argv on
# 127.0.0.1:PORT with the accept timeout TTL into the caller's array OUTARR
# (the transport's own BuildArgv: OUTARR must not start with __ths_/__THS_);
# rc = BuildArgv's. For a stand-alone listener (a port blocker, a "port free
# again" probe); the caller adds the redirections.
ths_listen_argv() {
    local __ths_rc=0
    ths_new_transport THSListenArgvT
    THSListenArgvT.Address = 127.0.0.1
    THSListenArgvT.Port = "$2"
    THSListenArgvT.ListenerTTL = "$3"
    THSListenArgvT.BuildArgv "$1" || __ths_rc=$?
    THSListenArgvT.delete
    return "$__ths_rc"
}

# ths_listening DIR [SLOT] — the server under DIR has a listener bound (its
# slot's stderr has the backend's THS_RE_BOUND line).
ths_listening() {
    local f
    ths_mark
    for f in "$1"/tmp/thttpserver.*/err"${2:-0}"; do
        if [[ -f "$f" ]] && grep -Eq "$THS_RE_BOUND" "$f" 2>/dev/null; then return 0; fi
    done
    return 1
}

# ths_prespawned DIR — some slot is listening with no connection yet (the
# pre-spawned listener of D5, while a request is being handled).
ths_prespawned() {
    local f
    ths_mark
    for f in "$1"/tmp/thttpserver.*/err[01]; do
        if [[ -f "$f" ]] && grep -Eq "$THS_RE_BOUND" "$f" 2>/dev/null && ! grep -Eq "$THS_RE_CONN" "$f" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# The server script: header + the test's SNIPPET + footer. The child gets
# UNIT, SRV_DIR, PORT, RT, MAXREQ, IDLE_BUDGET (+ KCL_NC) from the environment.
# Files in SRV_DIR: pid (the child's BASHPID), ticks (idle-tick counter),
# access.log (OnLog lines), result (rc/n/le of Serve + checks), ended.
ths_server_script() {   # FILE SNIPPET
    {
        cat <<'EOF'
exec </dev/null
cd "$SRV_DIR" || exit 90
source "$UNIT" || exit 91
printf '%s' "$BASHPID" > "$SRV_DIR/pid"
__t_ticks=0
__t_last=0
__t_idle() {
    local __t_n
    "$1.RequestCount"; __t_n="$RESULT"
    if [[ "$__t_n" != "$__t_last" ]]; then __t_last="$__t_n"; __t_ticks=0; fi
    __t_ticks=$(( __t_ticks + 1 ))
    if [[ -n "${TICK_HOOK:-}" ]]; then "$TICK_HOOK" "$1"; fi
    printf '%s\n' "$__t_ticks" > "$SRV_DIR/ticks"
    if [[ -e "$SRV_DIR/done" ]] || (( __t_ticks >= ${IDLE_BUDGET:-40} )); then "$1.Terminate"; fi
    return 0
}
__t_log() { printf '%s\n' "$2" >> "$SRV_DIR/access.log"; }
THttpServer.new S
S.Address = 127.0.0.1
S.Port = "$PORT"
S.AcceptIdleTimeout = 1000
S.RequestTimeout = "${RT:-10}"
S.MaxRequests = "${MAXREQ:-0}"
S.OnAcceptIdle = __t_idle
S.OnLog = __t_log
EOF
        printf '%s\n' "$2"
        cat <<'EOF'
if [[ -z "${NO_SERVE:-}" ]]; then
    __t_rc=0; S.Serve || __t_rc=$?
    S.LastError; __t_le="$RESULT"; S.RequestCount; __t_n="$RESULT"
    printf 'rc=%s\nn=%s\nle=%s\n' "$__t_rc" "$__t_n" "$__t_le" >> "$SRV_DIR/result"
fi
if [[ -n "${AFTER_HOOK:-}" ]]; then "$AFTER_HOOK"; fi
if declare -F S.delete >/dev/null; then S.delete; fi
: > "$SRV_DIR/ended"
EOF
    } > "$1"
}

# ths_start NAME SNIPPET [VAR=VALUE…] — write and start a server child under
# $TMP/NAME on a random port; wait until its first listener is bound (or the
# child ended). A bind failure (another test took the port) retries with a new
# port, up to 5 times. Sets THS_DIR, THS_PORT, THS_PID. rc 1 if it never
# listened (the child's files stay for the message).
ths_start() {
    local name="$1" snippet="$2" try
    shift 2
    THS_DIR="$TMP/$name"
    for (( try = 0; try < 5; try++ )); do
        rm -rf "$THS_DIR"
        mkdir -p "$THS_DIR/tmp"
        ths_server_script "$THS_DIR/srv.sh" "$snippet"
        ths_nport
        if (( THS_NC_ENV )); then
            env "$@" KCL_NC="$THS_NC" UNIT="$UNIT" SRV_DIR="$THS_DIR" PORT="$THS_PORT" TMPDIR="$THS_DIR/tmp" \
                timeout 180 "$BASH" "$THS_DIR/srv.sh" >"$THS_DIR/out" 2>"$THS_DIR/err" </dev/null &
        else
            env "$@" UNIT="$UNIT" SRV_DIR="$THS_DIR" PORT="$THS_PORT" TMPDIR="$THS_DIR/tmp" \
                timeout 180 "$BASH" "$THS_DIR/srv.sh" >"$THS_DIR/out" 2>"$THS_DIR/err" </dev/null &
        fi
        THS_PID=$!
        if ths_poll 170 ths_started; then
            if ths_listening "$THS_DIR"; then return 0; fi
            ths_mark
            if grep -Eq "$THS_RE_BINDFAIL" "$THS_DIR/result" 2>/dev/null; then
                wait "$THS_PID" 2>/dev/null
                continue
            fi
        fi
        return 1
    done
    return 1
}
ths_started() { ths_listening "$THS_DIR" || [[ -e "$THS_DIR/ended" ]] || ! kill -0 "$THS_PID" 2>/dev/null; }

# ths_launch NAME SCRIPT [ARG…] — the P3 form of ths_start for a WHOLE script
# (an application script written by 006, or an examples/ demo): start SCRIPT
# as the child under $TMP/NAME with the ARGs as its argv — every `{PORT}` in
# an ARG becomes the random port — and wait until its first listener is bound
# (or the child ended). The child gets UNIT_DIR, SRV_DIR, PORT, TMPDIR
# (+ KCL_NC) from the environment — with THS_OWN_NC=1, KCL_NC is REMOVED from
# its environment instead, so the script must find nc itself (the demos' own
# resolution); stdout/stderr go to SRV_DIR/out and /err. A
# bind failure — the line in SRV_DIR/result or in the child's stderr — retries
# with a new port, up to 5 times. Sets THS_DIR, THS_PORT, THS_PID; rc 1 if it
# never listened.
ths_launch() {
    local name="$1" script="$2" try a
    local -a args envs
    shift 2
    THS_DIR="$TMP/$name"
    for (( try = 0; try < 5; try++ )); do
        rm -rf "$THS_DIR"
        mkdir -p "$THS_DIR/tmp"
        ths_nport
        args=()
        for a in "$@"; do args+=("${a//\{PORT\}/$THS_PORT}"); done
        envs=(UNIT_DIR="$UNIT_DIR" SRV_DIR="$THS_DIR" PORT="$THS_PORT" TMPDIR="$THS_DIR/tmp")
        if [[ "${THS_OWN_NC:-0}" == 1 ]]; then
            envs=(-u KCL_NC "${envs[@]}")
        elif (( THS_NC_ENV )); then
            envs+=(KCL_NC="$THS_NC")
        fi
        env "${envs[@]}" timeout 180 "$BASH" "$script" "${args[@]}" >"$THS_DIR/out" 2>"$THS_DIR/err" </dev/null &
        THS_PID=$!
        if ths_poll 170 ths_started; then
            if ths_listening "$THS_DIR"; then return 0; fi
            ths_mark
            if grep -Eq "$THS_RE_BINDFAIL" "$THS_DIR/result" "$THS_DIR/err" 2>/dev/null; then
                wait "$THS_PID" 2>/dev/null
                continue
            fi
        fi
        return 1
    done
    return 1
}

# Process helpers — ONE kt_proc_snapshot each (ktests/ktest_proc.sh: /proc on
# cygwin and Linux, one `ps` elsewhere); the caller's REPLY is kept. On no
# backend the result variable is empty and the rc is 1.
#
# ths_children_pids PID — THS_CPIDS = the pids whose parent is PID,
# space-separated, numerically ascending.
ths_children_pids() {
    local __ths_reply=${REPLY-} __ths_p __ths_i
    local -a __ths_a=()
    THS_CPIDS=""
    kt_proc_snapshot || { REPLY=$__ths_reply; return 1; }
    for __ths_p in "${!KT_PROC_PP[@]}"; do
        if [[ "${KT_PROC_PP[$__ths_p]}" == "$1" ]]; then
            # insertion into the numerically ascending list (no fork, no sort)
            __ths_i=${#__ths_a[@]}
            while (( __ths_i > 0 )) && (( __ths_a[__ths_i - 1] > __ths_p )); do
                __ths_a[__ths_i]=${__ths_a[__ths_i - 1]}; __ths_i=$(( __ths_i - 1 ))
            done
            __ths_a[__ths_i]=$__ths_p
        fi
    done
    THS_CPIDS="${__ths_a[*]}"
    REPLY=$__ths_reply
    return 0
}

# ths_children_of PID — THS_NCHILD = how many processes have PID as parent.
ths_children_of() {
    local __ths_reply=${REPLY-} __ths_p
    THS_NCHILD=""
    kt_proc_snapshot || { REPLY=$__ths_reply; return 1; }
    THS_NCHILD=0
    for __ths_p in "${!KT_PROC_PP[@]}"; do
        if [[ "${KT_PROC_PP[$__ths_p]}" == "$1" ]]; then THS_NCHILD=$(( THS_NCHILD + 1 )); fi
    done
    REPLY=$__ths_reply
    return 0
}

# ths_child_of PID — the pid of PID's child process (the bash that `timeout`
# runs) into THS_CPID: the numerically lowest; '' (rc 1) if none.
ths_child_of() {
    local __ths_reply=${REPLY-} __ths_p
    THS_CPID=""
    kt_proc_snapshot || { REPLY=$__ths_reply; return 1; }
    for __ths_p in "${!KT_PROC_PP[@]}"; do
        if [[ "${KT_PROC_PP[$__ths_p]}" == "$1" ]]; then
            if [[ -z "$THS_CPID" ]] || (( __ths_p < THS_CPID )); then THS_CPID=$__ths_p; fi
        fi
    done
    REPLY=$__ths_reply
    [[ -n "$THS_CPID" ]]
}

# ths_fdcount — THS_NFD = the open fds of this shell: /proc/$BASHPID/fd
# (cygwin, Linux), else /dev/fd (FreeBSD fdescfs, macOS); '' and rc 1 if neither.
ths_fdcount() {
    local -a __ths_f
    THS_NFD=""
    if [[ -d /proc/$BASHPID/fd ]]; then
        __ths_f=(/proc/$BASHPID/fd/*)
    elif [[ -d /dev/fd ]]; then
        __ths_f=(/dev/fd/*)
    else
        return 1
    fi
    THS_NFD=${#__ths_f[@]}
}

# ths_int_ignored — rc 0 when a server child started the way ths_start starts
# it (in the background, through `env … timeout`) has SIGINT ignored on entry:
# GNU coreutils 9.10 `timeout` (Fedora) keeps an inherited SIG_IGN, and bash
# cannot trap a signal ignored on entry (measured L2.7-N2 on kb-fedora;
# coreutils 9.4 on Ubuntu, Windows: not ignored). A one-shot probe, cached in
# THS_INT_IGN (1 / 0) by the first call.
THS_INT_IGN=""
ths_int_ignored() {
    local o="" f="$TMP/.ths_int_probe"
    if [[ -z "$THS_INT_IGN" ]]; then
        env timeout 10 "$BASH" -c 'trap ": probe" INT; trap -p INT' >"$f" 2>/dev/null </dev/null &
        wait "$!" 2>/dev/null
        o="$(<"$f")"
        rm -f "$f"
        if [[ "$o" == *"trap -- '' SIGINT"* ]]; then THS_INT_IGN=1; else THS_INT_IGN=0; fi
    fi
    [[ "$THS_INT_IGN" == 1 ]]
}

# ths_custom_traps TRAPS — rc 0 when TRAPS (a server child's `trap -p INT TERM
# PIPE`, '|'-joined) shows the fixture's custom traps ': custom int', ': custom
# term' and ': custom pipe' — INT as ignored (`trap -- '' SIGINT`) instead
# ONLY when ths_int_ignored says a child gets SIGINT ignored on entry. The
# callers still compare the traps before and after for equality.
ths_custom_traps() {
    [[ "$1" == *"custom term"*"custom pipe"* ]] || return 1
    if [[ "$1" == *"custom int"* ]]; then
        return 0
    fi
    [[ "$1" == *"trap -- '' SIGINT"* ]] && ths_int_ignored
}

# ths_reap SECONDS — wait up to SECONDS for the child to end by itself; if it
# is still alive then, TERM the bash under `timeout` (the server stops at its
# next ≤ 1 s tick) and reap it. THS_RC = the exit status; THS_TERMED = 1 when
# the TERM was needed.
ths_reap() {
    THS_TERMED=0
    if ! ths_poll "$1" eval '! kill -0 "$THS_PID" 2>/dev/null'; then
        THS_TERMED=1
        if ths_child_of "$THS_PID"; then
            kill -TERM "$THS_CPID" 2>/dev/null
        else
            kill -TERM "$THS_PID" 2>/dev/null
        fi
    fi
    THS_RC=0
    wait "$THS_PID" 2>/dev/null || THS_RC=$?
}

# ths_finish — let the server end (the `done` marker → Terminate at the next
# idle tick) and reap it. THS_RC = the child's exit status.
ths_finish() {
    : > "$THS_DIR/done"
    THS_RC=0
    wait "$THS_PID" 2>/dev/null || THS_RC=$?
}

# ths_result KEY — a value from the child's result file into THS_V.
ths_result() {
    local l
    THS_V=""
    [[ -f "$THS_DIR/result" ]] || return 1
    while IFS= read -r l; do
        if [[ "$l" == "$1="* ]]; then THS_V="${l#*=}"; return 0; fi
    done < "$THS_DIR/result"
    return 1
}

# ths_curl OUT ARGS… — curl to the current server; retries ONLY on rc 7.
# CURL_RC, CURL_CODE (http_code).
ths_curl() {
    local out="$1" i
    shift
    for (( i = 0; i < 60; i++ )); do
        CURL_RC=0
        CURL_CODE="$(curl --noproxy '*' -s -m 30 -o "$out" -w '%{http_code}' "$@")" || CURL_RC=$?
        if (( CURL_RC != 7 )); then return 0; fi
        sleep 0.1
    done
    return 0
}

# ths_retry_refused CMD… — run CMD, a hand-made /dev/tcp client whose rc 7
# means "connect refused", again while it returns 7 (≤ 60 × 0.1 s); rc = its
# last rc. The next listener (the D5 pre-spawn, one nc per connection) may not
# have bound yet when the previous response has arrived: a one-shot connect
# right after a response can be refused (L3.5-7-o1: kb-freebsd, 004 case 12,
# 1 of 12 suite runs) — the §4 rule "retry only on a refused connect".
# A retried client lands on a listener that has only just bound: a second
# client sent right behind it can queue in the same one-accept backlog and be
# reset (GNU nc, see the 8-client case of 004): 007 case 8 with this retry
# failed once with curl code 000 (kb-freebsd, 1 of 32 runs), so it has none.
ths_retry_refused() {
    local i r=0
    for (( i = 0; i < 60; i++ )); do
        r=0; "$@" || r=$?
        if (( r != 7 )); then return "$r"; fi
        sleep 0.1
    done
    return "$r"
}

# ths_raw OUT REQUEST — a raw /dev/tcp client: connect (retry while refused),
# send REQUEST byte for byte, read to EOF into OUT (≤ 30 s).
# RAW_RC: 0 read to EOF · 7 never connected · 124 no EOF within 30 s.
ths_raw() {
    local out="$1" req="$2" i
    for (( i = 0; i < 60; i++ )); do
        RAW_RC=0
        ( exec 3<>"/dev/tcp/127.0.0.1/$THS_PORT" || exit 7
          printf '%s' "$req" >&3
          timeout 30 cat <&3 >"$out" ) 2>/dev/null || RAW_RC=$?
        if (( RAW_RC != 7 )); then return 0; fi
        sleep 0.1
    done
    return 0
}

# ths_rawf OUT FILE — ths_raw with the request taken byte for byte from FILE
# (a request with a NUL cannot live in a bash variable).
ths_rawf() {
    local out="$1" f="$2" i
    for (( i = 0; i < 60; i++ )); do
        RAW_RC=0
        ( exec 3<>"/dev/tcp/127.0.0.1/$THS_PORT" || exit 7
          cat "$f" >&3
          timeout 30 cat <&3 >"$out" ) 2>/dev/null || RAW_RC=$?
        if (( RAW_RC != 7 )); then return 0; fi
        sleep 0.1
    done
    return 0
}

# ths_split FILE — the header block of a captured response (CR removed) into
# THS_HEAD, the rest into THS_BODY.
ths_split() {
    local r
    r="$(<"$1")"
    THS_HEAD="${r%%$'\r\n\r\n'*}"
    THS_HEAD="${THS_HEAD//$'\r'/}"
    if [[ "$r" == *$'\r\n\r\n'* ]]; then THS_BODY="${r#*$'\r\n\r\n'}"; else THS_BODY=""; fi
}
