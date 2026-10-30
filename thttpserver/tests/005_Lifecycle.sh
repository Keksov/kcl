#!/usr/bin/env bash
# 005_Lifecycle.sh — thttpserver P2: what a Serve leaves behind, and signals
# (PLAN §2.5 Shutdown, §2.6, §3 facts 10 (server path) and 11).
#
#   §1 a clean Serve (MaxRequests), then a second Serve on the SAME port right
#      away: traps identical, fd count unchanged, no child process, no temp
#      dir, no request/response/transport instance; after S.delete no S_*.
#   §2 TERM while request 1 is handled and client 2 sits in the pre-spawned
#      listener: request 1 is answered, client 2 is closed without a response,
#      Serve returns 0, the child exits cleanly, the port is free.
#   §3 TERM while idle in Accept with AcceptIdleTimeout 0 (no idle ticks at
#      all): the child still ends on its own.
#   §5 N listener spawns leave no process-substitution FIFO (`sh-np.*`) in
#      TMPDIR, while serving or after (launch L3.5-7; N/A where `<( )` is
#      /dev/fd).
#   §6 a slot's stdin relay (`cat`) that has not seen its EOF — made
#      deterministic by stopping it — never reads the slot's next FIFO: each
#      listener gets a fresh one, the next responses are clean (launch L3.5-10).
#
# The checks that must run INSIDE the server shell (traps, fds, children,
# instances) are made by the child and written to its result file.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KTESTS_LIB_DIR="$SCRIPT_DIR/../../../ktests"
source "$KTESTS_LIB_DIR/ktest.sh"

UNIT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT="$UNIT_DIR/thttpserver.sh"

TEST_NAME="$(basename "$0" .sh)"
kt_test_init "$TEST_NAME" "$SCRIPT_DIR" "$@"

exec </dev/null

TMP="$(cd "$(kt_fixture_tmpdir)" && pwd)"
export THS_LIB="$SCRIPT_DIR/_ths_socket.sh"
source "$THS_LIB"
CRLF=$'\r\n'
cd "$TMP" || exit 1

kt_test_section "005: lifecycle — leaks, traps, port release, TERM (P2)"

# The child-side probe: `chk TAG` appends TAG_traps / _fds / _children /
# _dirs / _left to the result file. Fork-free except the one $(trap -p).
CHK='
source "$THS_LIB"
chk() {
    local t n d dirs="" v left=""
    t="$(trap -p INT TERM PIPE)"
    ths_fdcount
    ths_children_of $BASHPID; n=$THS_NCHILD
    for d in "$TMPDIR"/thttpserver.*; do if [[ -e "$d" ]]; then dirs+=" $d"; fi; done
    for v in S_req_data S_req_class S_req_hdr S_req_hdrn S_req_qf S_req_rp S_resp_data S_resp_class S_resp_hdr S_resp_hdrn S_tr_data S_tr_class; do
        if declare -p "$v" >/dev/null 2>&1; then left+=" $v"; fi
    done
    if declare -F S_req.Method >/dev/null; then left+=" S_req.Method"; fi
    if declare -F S_tr.Accept >/dev/null; then left+=" S_tr.Accept"; fi
    printf "%s_traps=%s\n%s_fds=%s\n%s_children=%s\n%s_dirs=[%s]\n%s_left=[%s]\n" \
        "$1" "${t//$'"'"'\n'"'"'/|}" "$1" "$THS_NFD" "$1" "$n" "$1" "$dirs" "$1" "$left" >> "$SRV_DIR/result"
}
'

# ===========================================================================
kt_test_section "1. a clean Serve, then the same port again at once (fact 10, server path)"
# ===========================================================================

L1_TITLES=(
    "two requests served, Serve (MaxRequests 2) rc 0"
    "right after it, a second Serve binds the SAME port and serves (the port was released)"
    "traps INT/TERM/PIPE identical before and after each Serve (custom traps restored exactly)"
    "the fd count of the server shell is unchanged after each Serve"
    "no child process, no temp dir, no request/response/transport instance after each Serve"
    "after S.delete: no S_* variable or function (server, stopwatch) is left"
    "the child's stderr is empty"
)
SNIP_L1="$CHK"'
NO_SERVE=1
l1() { $2.Write one; }
THttpRouter.new RT
RT.RegisterRoute /x GET l1
S.Router = RT
trap ": custom int" INT
trap ": custom term" TERM
trap ": custom pipe" PIPE
chk before
S.MaxRequests = 2
rc=0; S.Serve || rc=$?
printf "rc1=%s\n" "$rc" >> "$SRV_DIR/result"
chk after1
: > "$SRV_DIR/served1"
S.MaxRequests = 1
rc=0; S.Serve || rc=$?
printf "rc2=%s\n" "$rc" >> "$SRV_DIR/result"
chk after2
S.delete
RT.delete
left=""
for v in S_data S_class S_sw_data S_sw_class S_tr_data S_req_data S_resp_data; do
    if declare -p "$v" >/dev/null 2>&1; then left+=" $v"; fi
done
for fn in S.Serve S.Port S_sw.Restart S_tr.Accept; do
    if declare -F "$fn" >/dev/null; then left+=" $fn"; fi
done
printf "deleted_left=[%s]\n" "$left" >> "$SRV_DIR/result"
'

if ! ths_have_nc; then
    ths_skip "${L1_TITLES[@]}"
elif ! ths_start l1 "$SNIP_L1" IDLE_BUDGET=60; then
    for t in "${L1_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "server l1 never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null)"; done
else
    ths_curl "$TMP/l1a" "http://127.0.0.1:$THS_PORT/x"; ca="$CURL_CODE:$(<"$TMP/l1a")"
    ths_curl "$TMP/l1b" "http://127.0.0.1:$THS_PORT/x"; cb="$CURL_CODE:$(<"$TMP/l1b")"
    s1=0; ths_poll 60 test -e "$THS_DIR/served1" && s1=1
    l2=0; ths_poll 60 ths_listening "$THS_DIR" && l2=1
    ths_curl "$TMP/l1c" "http://127.0.0.1:$THS_PORT/x"; cc="$CURL_CODE:$(<"$TMP/l1c")"
    THS_RC=0; wait "$THS_PID" || THS_RC=$?
    declare -A R=()
    while IFS= read -r l; do [[ "$l" == *=* ]] && R["${l%%=*}"]="${l#*=}"; done < "$THS_DIR/result"

    kt_test_start "${L1_TITLES[0]}"
    if [[ "$ca $cb" == "200:one 200:one" && "${R[rc1]:-}" == 0 && $s1 -eq 1 ]]; then kt_test_pass "200 200, rc 0"; else kt_test_fail "$ca $cb rc1='${R[rc1]:-}' served1=$s1"; fi

    kt_test_start "${L1_TITLES[1]}"
    if [[ $l2 -eq 1 && "$cc" == "200:one" && "${R[rc2]:-}" == 0 && $THS_RC -eq 0 ]]; then kt_test_pass "listening again, 200, rc 0, child exit 0"; else kt_test_fail "listening=$l2 '$cc' rc2='${R[rc2]:-}' exit=$THS_RC"; fi

    kt_test_start "${L1_TITLES[2]}"
    tb="${R[before_traps]:-}"
    if ths_custom_traps "$tb" && [[ "${R[after1_traps]:-}" == "$tb" && "${R[after2_traps]:-}" == "$tb" ]]; then
        kt_test_pass "identical: $tb"
    else
        kt_test_fail "before='$tb' after1='${R[after1_traps]:-}' after2='${R[after2_traps]:-}'"
    fi

    kt_test_start "${L1_TITLES[3]}"
    if [[ -n "${R[before_fds]:-}" && "${R[after1_fds]:-}" == "${R[before_fds]}" && "${R[after2_fds]:-}" == "${R[before_fds]}" ]]; then
        kt_test_pass "${R[before_fds]} fds throughout"
    else
        kt_test_fail "fds ${R[before_fds]:-?} → ${R[after1_fds]:-?} → ${R[after2_fds]:-?}"
    fi

    kt_test_start "${L1_TITLES[4]}"
    bad=""
    for t in after1 after2; do
        [[ "${R[${t}_children]:-x}" == 0 ]] || bad+=" $t-children=${R[${t}_children]:-?}"
        [[ "${R[${t}_dirs]:-x}" == "[]" ]] || bad+=" $t-dirs=${R[${t}_dirs]:-?}"
        [[ "${R[${t}_left]:-x}" == "[]" ]] || bad+=" $t-left=${R[${t}_left]:-?}"
    done
    if [[ -z "$bad" ]]; then kt_test_pass "clean twice"; else kt_test_fail "$bad"; fi

    kt_test_start "${L1_TITLES[5]}"
    if [[ "${R[deleted_left]:-x}" == "[]" ]]; then kt_test_pass "nothing left"; else kt_test_fail "left: ${R[deleted_left]:-no line}"; fi

    kt_test_start "${L1_TITLES[6]}"
    e="$(<"$THS_DIR/err")"
    if [[ -z "$e" ]]; then kt_test_pass "empty"; else kt_test_fail "'${e:0:300}'"; fi
fi

# ===========================================================================
kt_test_section "2. TERM while the pre-spawned listener holds client 2 (fact 11)"
# ===========================================================================

L2_TITLES=(
    "client 2 connected (no refusal) while request 1 was being handled"
    "after TERM: request 1 is still answered (200)"
    "client 2 is closed WITHOUT a response (0 bytes, EOF)"
    "Serve returned 0, the child exited 0, empty LastError"
    "both slots reaped: no child process, no temp dir, no instance; traps identical to before Serve"
    "the port is free afterwards (a plain listener binds it)"
    "the child's stderr is empty"
)
SNIP_L2="$CHK"'
NO_SERVE=1
l2_hold() {
    source "$THS_LIB"
    ths_poll 60 ths_prespawned "$SRV_DIR" || { $2.Write no-prespawn; return 0; }
    : > "$SRV_DIR/ready"
    ths_poll 60 eval "[[ -n \$__THS_SIGNAL ]]" || { $2.Write no-signal; return 0; }
    $2.Write hold-done
}
THttpRouter.new RT
RT.RegisterRoute /hold GET l2_hold
S.Router = RT
trap ": custom term" TERM
chk before
rc=0; S.Serve || rc=$?
S.LastError
printf "rc=%s\nle=%s\n" "$rc" "$RESULT" >> "$SRV_DIR/result"
chk after
'

if ! ths_have_nc; then
    ths_skip "${L2_TITLES[@]}"
elif ! ths_start l2 "$SNIP_L2" IDLE_BUDGET=60; then
    for t in "${L2_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "server l2 never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null)"; done
else
    SPID="$(<"$THS_DIR/pid")"
    ths_raw "$TMP/t1.out" "GET /hold HTTP/1.0${CRLF}${CRLF}" &
    C1=$!
    rdy=0; ths_poll 60 test -e "$THS_DIR/ready" && rdy=1
    ( exec 3<>"/dev/tcp/127.0.0.1/$THS_PORT" || { : > "$TMP/t2.refused"; exit 7; }
      : > "$TMP/t2.conn"; printf 'GET /hold HTTP/1.0\r\n\r\n' >&3; "$KT_TIMEOUT" 30 cat <&3 > "$TMP/t2.out" ) 2>/dev/null &
    C2=$!
    ths_poll 30 eval '[[ -e $TMP/t2.conn || -e $TMP/t2.refused ]]'
    kill -TERM "$SPID" 2>/dev/null
    wait "$C1"; c2rc=0; wait "$C2" || c2rc=$?
    THS_RC=0; wait "$THS_PID" || THS_RC=$?
    declare -A R=()
    while IFS= read -r l; do [[ "$l" == *=* ]] && R["${l%%=*}"]="${l#*=}"; done < "$THS_DIR/result"

    kt_test_start "${L2_TITLES[0]}"
    if [[ $rdy -eq 1 && -e "$TMP/t2.conn" && ! -e "$TMP/t2.refused" ]]; then kt_test_pass "connected"; else kt_test_fail "ready=$rdy conn=$([[ -e $TMP/t2.conn ]] && echo y) refused=$([[ -e $TMP/t2.refused ]] && echo y)"; fi

    kt_test_start "${L2_TITLES[1]}"
    ths_split "$TMP/t1.out"
    if [[ "${THS_HEAD%%$'\n'*}" == "HTTP/1.1 200 OK" && "$THS_BODY" == hold-done ]]; then kt_test_pass "200 hold-done"; else kt_test_fail "'${THS_HEAD:0:40}' body='$THS_BODY'"; fi

    kt_test_start "${L2_TITLES[2]}"
    sz="$(wc -c < "$TMP/t2.out" 2>/dev/null)"
    sz="${sz//[[:space:]]/}"   # BSD wc pads the count with blanks
    if [[ "$sz" == 0 && $c2rc -eq 0 ]]; then kt_test_pass "0 bytes, EOF"; else kt_test_fail "bytes=$sz rc=$c2rc (124 = no EOF)"; fi

    kt_test_start "${L2_TITLES[3]}"
    if [[ "${R[rc]:-}" == 0 && -z "${R[le]-x}" && $THS_RC -eq 0 ]]; then kt_test_pass "rc 0, exit 0"; else kt_test_fail "rc='${R[rc]:-}' le='${R[le]-none}' exit=$THS_RC"; fi

    kt_test_start "${L2_TITLES[4]}"
    if [[ "${R[after_children]:-x}" == 0 && "${R[after_dirs]:-x}" == "[]" && "${R[after_left]:-x}" == "[]" \
          && -n "${R[before_traps]:-}" && "${R[after_traps]:-}" == "${R[before_traps]}" ]]; then
        kt_test_pass "clean; traps '${R[after_traps]}'"
    else
        kt_test_fail "children=${R[after_children]:-?} dirs=${R[after_dirs]:-?} left=${R[after_left]:-?} traps '${R[before_traps]:-}' → '${R[after_traps]:-}'"
    fi

    kt_test_start "${L2_TITLES[5]}"
    PRA=(); ths_listen_argv PRA "$THS_PORT" 1
    "${PRA[@]}" >/dev/null 2>"$TMP/probe.err" </dev/null
    ths_mark
    if grep -Eq "$THS_RE_BOUND" "$TMP/probe.err"; then kt_test_pass "bound"; else kt_test_fail "probe: $(tr '\n' ' ' < "$TMP/probe.err")"; fi

    kt_test_start "${L2_TITLES[6]}"
    e="$(<"$THS_DIR/err")"
    if [[ -z "$e" ]]; then kt_test_pass "empty"; else kt_test_fail "'${e:0:300}'"; fi
fi

# ===========================================================================
kt_test_section "3. TERM while idle in Accept, AcceptIdleTimeout 0 (no ticks)"
# ===========================================================================

L3_TITLES=(
    "the child ends on its own after TERM: Serve rc 0, exit 0, nothing served"
    "no child process and no temp dir left; stderr empty"
)
SNIP_L3='
source "$THS_LIB"
S.AcceptIdleTimeout = 0
l3_after() { local n d dirs=""; ths_children_of $BASHPID; n=$THS_NCHILD
    for d in "$TMPDIR"/thttpserver.*; do [[ -e "$d" ]] && dirs+=" $d"; done
    printf "children=%s\ndirs=[%s]\n" "$n" "$dirs" >> "$SRV_DIR/result"; }
AFTER_HOOK=l3_after
'
if ! ths_have_nc; then
    ths_skip "${L3_TITLES[@]}"
elif ! ths_start l3 "$SNIP_L3"; then
    for t in "${L3_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "server l3 never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null)"; done
else
    kill -TERM "$(<"$THS_DIR/pid")" 2>/dev/null
    THS_RC=0; wait "$THS_PID" || THS_RC=$?
    ths_result rc; rc="$THS_V"; ths_result n; n="$THS_V"; ths_result children; ch="$THS_V"; ths_result dirs; dd="$THS_V"

    kt_test_start "${L3_TITLES[0]}"
    if [[ $THS_RC -eq 0 && "$rc" == 0 && "$n" == 0 ]]; then kt_test_pass "rc 0, exit 0, 0 served"; else kt_test_fail "exit=$THS_RC (124 = the guard fired) rc='$rc' n='$n'"; fi

    kt_test_start "${L3_TITLES[1]}"
    e="$(<"$THS_DIR/err")"
    if [[ "$ch" == 0 && "$dd" == "[]" && -z "$e" ]]; then kt_test_pass "clean"; else kt_test_fail "children=$ch dirs=$dd stderr='${e:0:200}'"; fi
fi

# ===========================================================================
kt_test_section "4. Shutdown with only a LISTENING slot is not drained (review R1)"
# ===========================================================================

# A connected slot is closed the drained way (bounded by CloseTimeout, fact 11
# above); a slot that is only listening must be killed at once — its stdin
# EOF would not end nc's accept. Timed in the child, fork-free (EPOCHREALTIME
# into variables around the one direct call), loose ceiling: 1.5 s against a
# CloseTimeout of 5 s.
L4_TITLES=(
    "Shutdown of a transport whose only slot is listening: well under CloseTimeout (< 1.5 s of 5 s), listener reaped, dir removed"
)
SNIP_L4='
source "$THS_LIB"
NO_SERVE=1
ths_new_transport T
T.Port = "$PORT"
T.CloseTimeout = 5
r=0; T.Accept 1000 10 || r=$?
t0=${EPOCHREALTIME//[!0-9]/}
T.Shutdown
t1=${EPOCHREALTIME//[!0-9]/}
T.LastError
ths_children_of $BASHPID; l4_n=$THS_NCHILD
l4_d=""; for d in "$TMPDIR"/thttpserver.*; do [[ -e "$d" ]] && l4_d+=" $d"; done
printf "accept=%s\nshutdown_us=%s\nle=%s\nchildren=%s\ndirs=[%s]\n" "$r" "$(( t1 - t0 ))" "$RESULT" "$l4_n" "$l4_d" >> "$SRV_DIR/result"
T.delete
'
if ! ths_have_nc; then
    ths_skip "${L4_TITLES[@]}"
elif ! ths_start l4 "$SNIP_L4"; then
    for t in "${L4_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "l4 never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null) $(tr '\n' ' ' < "$THS_DIR/result" 2>/dev/null)"; done
else
    THS_RC=0; wait "$THS_PID" || THS_RC=$?
    ths_result accept; ac="$THS_V"; ths_result shutdown_us; us="$THS_V"; ths_result children; ch="$THS_V"; ths_result dirs; dd="$THS_V"
    e="$(<"$THS_DIR/err")"
    kt_test_start "${L4_TITLES[0]}"
    if [[ $THS_RC -eq 0 && "$ac" == 1 && "$us" =~ ^[0-9]+$ ]] && (( us < 1500000 )) && [[ "$ch" == 0 && "$dd" == "[]" && -z "$e" ]]; then
        kt_test_pass "idle tick, then Shutdown in $(( us / 1000 )) ms; clean"
    else
        kt_test_fail "exit=$THS_RC accept=$ac shutdown_us=$us children=$ch dirs=$dd stderr='${e:0:200}'"
    fi
fi

# ===========================================================================
kt_test_section "5. no process-substitution FIFO left in TMPDIR after N spawns (launch L3.5-7, PORTING H44)"
# ===========================================================================
# Where `<( )` is a FIFO in TMPDIR (FreeBSD's pkg bash) the relay's
# substitution used to stay behind as one `sh-np.*` per listener spawn: the
# shell that made it became the listener by `exec` and never unlinked it.
# While serving, a live listener still has ONE such entry: the reader
# substitution the server shell opened (`exec {rd}< <(…)`), which bash
# unlinks when that listener ends — so at most one per slot (2) mid-run, and
# none after Serve; the leak grew by one per spawn. N/A where `<( )` is /dev/fd (the same checks run, nothing can be left).
# The kind is read by OPENING the path (a bare `echo <(:)` would leave the
# writer blocked in open() for ever on a FIFO bash).

l5_kind() { L5_PS="$1"; : < "$1"; }
l5_kind <(:)
if [[ "$L5_PS" == /dev/fd/* ]]; then L5_NA=" (N/A: <( ) is $L5_PS)"; else L5_NA=" (<( ) is a FIFO: ${L5_PS##*/})"; fi
L5_N=6
L5_TITLES=(
    "MaxRequests $L5_N served (one listener spawn per request): at most one sh-np.* per slot while serving (a live listener's reader), TMPDIR empty after Serve"
)
SNIP_L5='
l5() { $2.Write five; }
THttpRouter.new RT
RT.RegisterRoute /x GET l5
S.Router = RT
'
# l5_fifos — the sh-np.* entries of the server's TMPDIR into L5_F; rc 0 = at
# most 2 (one live listener's reader per slot)
l5_fifos() { local f n=0; L5_F=""; for f in "$THS_DIR"/tmp/sh-np.*; do if [[ -e "$f" || -p "$f" ]]; then L5_F+=" ${f##*/}"; n=$(( n + 1 )); fi; done; (( n <= 2 )); }
if ! ths_have_nc; then
    ths_skip "${L5_TITLES[@]}"
elif ! ths_start l5 "$SNIP_L5" MAXREQ="$L5_N" IDLE_BUDGET=60; then
    for t in "${L5_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "l5 never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null)"; done
else
    codes=""; mid=""; want=""
    for (( i = 1; i <= L5_N; i++ )); do want+=" 200"; done
    for (( i = 1; i <= L5_N; i++ )); do
        ths_curl "$TMP/l5.$i" "http://127.0.0.1:$THS_PORT/x"; codes+=" $CURL_CODE"
        if (( i == L5_N - 1 )); then
            # the next listener is pre-spawned by now (D5); a leak never goes
            # away (it would be one per spawn so far: L5_N)
            ths_poll 30 ths_prespawned "$THS_DIR" || :
            ths_poll 2 l5_fifos || mid="$L5_F"
        fi
    done
    THS_RC=0; wait "$THS_PID" || THS_RC=$?
    ths_result rc; rc="$THS_V"; ths_result n; n="$THS_V"
    left="$(ls -A "$THS_DIR/tmp")"
    e="$(<"$THS_DIR/err")"
    kt_test_start "${L5_TITLES[0]}"
    if [[ $THS_RC -eq 0 && "$rc" == 0 && "$n" == "$L5_N" && "$codes" == "$want" && -z "$mid" && -z "$left" && -z "$e" ]]; then
        kt_test_pass "$L5_N served; mid-run [${L5_F# }]; nothing left after$L5_NA"
    else
        kt_test_fail "exit=$THS_RC rc=$rc n=$n codes='$codes' mid='$mid' tmp='${left//$'\n'/ }' stderr='${e:0:200}'$L5_NA"
    fi
fi

# ===========================================================================
kt_test_section "6. a stdin relay that has not seen its EOF never reads the slot's next FIFO (launch L3.5-10)"
# ===========================================================================
# A slot's listener reads its FIFO through a `cat` relay — the listener's
# child, not the server's. When the slot closes, that cat ends only once it
# has RUN and seen the EOF of the closed writer. With one FIFO per slot, the
# next spawn of the same slot opened a new writer on the same FIFO, which
# clears a pending EOF: an old cat that had not run by then read on as a
# second reader (kb-freebsd: it took the status line of the next response on
# that slot, 2 of 36 suite runs). Each listener now gets a fresh FIFO.
# Made deterministic here: the relay of a silent client's slot is STOPPED
# (it can see nothing), the 408 goes into its FIFO, the slot closes. On a
# reused FIFO that stopped reader keeps the FIFO — and the 408 in it — alive,
# and the slot's next generation sends those stale bytes ahead of the next
# response on that slot (request 2 below; request 1 takes the other slot).
# On a fresh FIFO both requests are clean; once continued, the old relay ends
# by itself (nobody will ever write its FIFO again). RequestTimeout 6 s
# leaves time to find and stop the relay before the 408 (slow Windows: a
# /proc scan); an EXIT hook continues and kills a stopped relay if the test
# dies before its own cleanup.
L6_TITLES=(
    "a silent client's slot with its relay cat STOPPED: the 408 goes into that FIFO, the slot closes — the next two requests (one per slot) are a clean 200 each (no stale 408), and the old relay, continued, ends by itself"
)
SNIP_L6='
l6() { $2.Write six; }
THttpRouter.new RT
RT.RegisterRoute /x GET l6
S.Router = RT
'
# l6_client — a silent client: connect, send nothing, read to EOF (rc 7 =
# refused). l6_conn — some slot of the server has accepted it. l6_one — the
# server's FIFOs have exactly one cat reader (until the 408 only the current
# slot has a listener) → L6_CAT.
l6_client() { ( exec 3<>"/dev/tcp/127.0.0.1/$THS_PORT" || exit 7; "$KT_TIMEOUT" -k 5 30 cat <&3 > "$TMP/l6.silent" ) 2>/dev/null; }
l6_conn() { local f; for f in "$THS_DIR"/tmp/thttpserver.*/err[01]; do if [[ -f "$f" ]] && grep -Eq "$THS_RE_CONN" "$f" 2>/dev/null; then return 0; fi; done; return 1; }
l6_one() { kt_proc_pids "$THS_DIR/tmp/thttpserver."; L6_FOUND="$REPLY"; [[ "$REPLY" =~ ^[0-9]+$ ]]; }
l6_gone() { ! kill -0 "$L6_CAT" 2>/dev/null; }
# l6_release — a relay this test stopped is continued and killed (cleanup and
# the EXIT hook; a stray otherwise)
l6_release() {
    if [[ -n "$L6_CAT" ]] && kill -0 "$L6_CAT" 2>/dev/null; then
        kill -CONT "$L6_CAT" 2>/dev/null; kill -KILL "$L6_CAT" 2>/dev/null
    fi
    return 0
}
l6_rc() { return "$1"; }
if ! ths_have_nc; then
    ths_skip "${L6_TITLES[@]}"
elif ! kt_proc_init; then
    for t in "${L6_TITLES[@]}"; do kt_test_start "$t"; kt_test_pass "SKIP: no process backend: $KT_PROC_WHY"; done
elif ! ths_start l6 "$SNIP_L6" RT=6 IDLE_BUDGET=60; then
    for t in "${L6_TITLES[@]}"; do kt_test_start "$t"; kt_test_fail "l6 never listened: $(tr '\n' ' ' < "$THS_DIR/err" 2>/dev/null)"; done
else
    ths_mark
    L6_CAT=""; L6_FOUND=""; why=""; gone=n; r1=""; r2=""
    # the EXIT hook: l6_release, then the framework's own EXIT trap with $? kept
    eval "L6_TA=($(trap -p EXIT))"; L6_OLDEXIT="${L6_TA[2]-}"
    trap '_l6rc=$?; l6_release; l6_rc "$_l6rc"; eval "$L6_OLDEXIT"' EXIT
    ths_retry_refused l6_client & L6_CP=$!
    if ! ths_poll 10 l6_conn; then
        why="the silent client was never accepted"
    elif ! ths_poll 3 l6_one; then
        why="expected one relay cat, found '$L6_FOUND'"
    else
        L6_CAT="$L6_FOUND"
        kill -STOP "$L6_CAT" 2>/dev/null || why="kill -STOP $L6_CAT failed"
    fi
    wait "$L6_CP" 2>/dev/null
    ths_raw "$TMP/l6.1" "GET /x HTTP/1.0${CRLF}${CRLF}"; r1="$(<"$TMP/l6.1")"
    ths_raw "$TMP/l6.2" "GET /x HTTP/1.0${CRLF}${CRLF}"; r2="$(<"$TMP/l6.2")"
    if [[ -n "$L6_CAT" ]]; then
        kill -CONT "$L6_CAT" 2>/dev/null
        if ths_poll 5 l6_gone; then gone=y; fi
    fi
    l6_release
    if [[ -n "$L6_OLDEXIT" ]]; then trap -- "$L6_OLDEXIT" EXIT; else trap - EXIT; fi
    ths_finish
    ths_result rc; rc="$THS_V"
    e="$(<"$THS_DIR/err")"
    kt_test_start "${L6_TITLES[0]}"
    if [[ -z "$why" && "$r1" == "HTTP/1.1 200 OK"*$'\r\n\r\n'six && "$r2" == "HTTP/1.1 200 OK"*$'\r\n\r\n'six \
          && "$r1$r2" != *408* && $gone == y && $THS_RC -eq 0 && "$rc" == 0 && -z "$e" ]]; then
        kt_test_pass "200 + 200, nothing stale; the continued relay ended by itself"
    else
        r1="${r1//$'\r'/}"; r2="${r2//$'\r'/}"
        kt_test_fail "${why:+$why; }r1='${r1//$'\n'/|}' r2='${r2//$'\n'/|}' relay $L6_CAT gone-after-CONT=$gone exit=$THS_RC rc=$rc stderr='${e:0:200}'"
    fi
fi
