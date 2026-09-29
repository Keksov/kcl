#!/bin/bash
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
#   * nc = KCL_NC, else `nc` on PATH, else /c/bin/msys64/usr/bin/nc.exe
#     (exported to the child as KCL_NC); with none the socket cases SKIP
#     visibly (kt_test_pass "SKIP: …"), so the case count stays the same.

unset -v HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy FTP_PROXY ftp_proxy

# THS_NC — the netcat the children use; THS_NC_ENV — 1 when it must reach the
# child through KCL_NC (not found on PATH).
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

# ths_have_nc — rc 0 when the socket cases can run.
ths_have_nc() { [[ -n "$THS_NC" ]]; }

# ths_skip TITLE… — one visible SKIP case per title (the case count is kept).
ths_skip() {
    local t
    for t in "$@"; do
        kt_test_start "$t"
        kt_test_pass "SKIP: no netcat (KCL_NC unset, no nc on PATH, no /c/bin/msys64/usr/bin/nc.exe)"
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

# ths_listening DIR [SLOT] — the server under DIR has a listener bound (its
# slot's -vv stderr says `Listening on`).
ths_listening() {
    local f
    for f in "$1"/tmp/thttpserver.*/err"${2:-0}"; do
        if [[ -f "$f" ]] && grep -q '^Listening on' "$f" 2>/dev/null; then return 0; fi
    done
    return 1
}

# ths_prespawned DIR — some slot is listening with no connection yet (the
# pre-spawned listener of D5, while a request is being handled).
ths_prespawned() {
    local f
    for f in "$1"/tmp/thttpserver.*/err[01]; do
        if [[ -f "$f" ]] && grep -q '^Listening on' "$f" 2>/dev/null && ! grep -q '^Connection from' "$f" 2>/dev/null; then
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
            if grep -q "Couldn't setup listening socket" "$THS_DIR/result" 2>/dev/null; then
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
            if grep -q "Couldn't setup listening socket" "$THS_DIR/result" "$THS_DIR/err" 2>/dev/null; then
                wait "$THS_PID" 2>/dev/null
                continue
            fi
        fi
        return 1
    done
    return 1
}

# ths_child_of PID — the pid of PID's child process (the bash that `timeout`
# runs) into THS_CPID, fork-free through /proc/*/ppid; '' if none.
ths_child_of() {
    local p pp
    THS_CPID=""
    for p in /proc/[0-9]*; do
        pp=""; { read -r pp < "$p/ppid"; } 2>/dev/null || continue
        if [[ "$pp" == "$1" ]]; then THS_CPID="${p#/proc/}"; return 0; fi
    done
    return 1
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
