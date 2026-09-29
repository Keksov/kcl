#!/bin/bash
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
chk() {
    local t p pp n=0 d dirs="" v left=""
    t="$(trap -p INT TERM PIPE)"
    local -a f=(/proc/$BASHPID/fd/*)
    for p in /proc/[0-9]*; do
        pp=""; { read -r pp < "$p/ppid"; } 2>/dev/null || continue
        if [[ "$pp" == "$BASHPID" ]]; then n=$(( n + 1 )); fi
    done
    for d in "$TMPDIR"/thttpserver.*; do if [[ -e "$d" ]]; then dirs+=" $d"; fi; done
    for v in S_req_data S_req_class S_req_hdr S_req_hdrn S_req_qf S_req_rp S_resp_data S_resp_class S_resp_hdr S_resp_hdrn S_tr_data S_tr_class; do
        if declare -p "$v" >/dev/null 2>&1; then left+=" $v"; fi
    done
    if declare -F S_req.Method >/dev/null; then left+=" S_req.Method"; fi
    if declare -F S_tr.Accept >/dev/null; then left+=" S_tr.Accept"; fi
    printf "%s_traps=%s\n%s_fds=%s\n%s_children=%s\n%s_dirs=[%s]\n%s_left=[%s]\n" \
        "$1" "${t//$'"'"'\n'"'"'/|}" "$1" "${#f[@]}" "$1" "$n" "$1" "$dirs" "$1" "$left" >> "$SRV_DIR/result"
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
    if [[ "$tb" == *"custom int"*"custom term"*"custom pipe"* && "${R[after1_traps]:-}" == "$tb" && "${R[after2_traps]:-}" == "$tb" ]]; then
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
      : > "$TMP/t2.conn"; printf 'GET /hold HTTP/1.0\r\n\r\n' >&3; timeout 30 cat <&3 > "$TMP/t2.out" ) 2>/dev/null &
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
    "$THS_NC" -l -n -vv -w 1 -s 127.0.0.1 -p "$THS_PORT" >/dev/null 2>"$TMP/probe.err" </dev/null
    if grep -q '^Listening on' "$TMP/probe.err"; then kt_test_pass "bound"; else kt_test_fail "probe: $(tr '\n' ' ' < "$TMP/probe.err")"; fi

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
S.AcceptIdleTimeout = 0
l3_after() { local p pp n=0 d dirs=""; for p in /proc/[0-9]*; do pp=""; { read -r pp < "$p/ppid"; } 2>/dev/null || continue; [[ "$pp" == "$BASHPID" ]] && n=$(( n + 1 )); done
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
NO_SERVE=1
TNetcatTransport.new T
T.Port = "$PORT"
T.CloseTimeout = 5
r=0; T.Accept 1000 10 || r=$?
t0=${EPOCHREALTIME//[!0-9]/}
T.Shutdown
t1=${EPOCHREALTIME//[!0-9]/}
T.LastError
l4_n=0
for p in /proc/[0-9]*; do pp=""; { read -r pp < "$p/ppid"; } 2>/dev/null || continue; [[ "$pp" == "$BASHPID" ]] && l4_n=$(( l4_n + 1 )); done
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
